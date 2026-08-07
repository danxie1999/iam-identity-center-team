#!/usr/bin/env bash
# Integration tests for the TEAM Athena audit infrastructure stack
# (deployment/athena-audit.yml). Run after deploying the stack in the TEAM
# delegated administrator account:
#
#   ./athena-audit-test.sh [stack-name] [region]
#
# Requires: awscli, jq. Exits non-zero if any test fails.
set -uo pipefail

STACK_NAME="${1:-TEAM-AUDIT-INFRA}"
REGION="${2:-us-east-1}"
PASS=0
FAIL=0

check() { # $1 = description, $2 = 0/1 result (0=pass)
  if [ "$2" -eq 0 ]; then
    echo "PASS: $1"; PASS=$((PASS+1))
  else
    echo "FAIL: $1"; FAIL=$((FAIL+1))
  fi
}

out() { # $1 = output key
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text
}

echo "== Reading stack outputs ($STACK_NAME, $REGION) =="
GLUE_TABLE_ARN=$(out GlueTableArn)
WORKGROUP=$(out AthenaWorkGroup)
LOG_BUCKET=$(out TrailLogBucketName)
RESULTS_BUCKET=$(out AthenaResultsBucketName)
TRAIL_NAME=$(out TrailName)
TRAIL_ARN=$(out TrailArn)
DB=$(echo "$GLUE_TABLE_ARN" | awk -F'table/' '{print $2}' | cut -d/ -f1)
TABLE=$(echo "$GLUE_TABLE_ARN" | awk -F'table/' '{print $2}' | cut -d/ -f2)
[ -n "$GLUE_TABLE_ARN" ] && [ "$GLUE_TABLE_ARN" != "None" ]
check "Stack exists with GlueTableArn output" $?

# Test 1: trail is logging with no delivery errors
STATUS=$(aws cloudtrail get-trail-status --region "$REGION" --name "$TRAIL_ARN" --output json 2>/dev/null)
[ "$(echo "$STATUS" | jq -r '.IsLogging')" = "true" ]
check "Trail is logging" $?
[ "$(echo "$STATUS" | jq -r '.LatestDeliveryError // empty')" = "" ]
check "Trail has no delivery errors" $?

# Test 2: log bucket blocks public access
PAB=$(aws s3api get-public-access-block --bucket "$LOG_BUCKET" --output json 2>/dev/null)
[ "$(echo "$PAB" | jq -r '.PublicAccessBlockConfiguration | [.BlockPublicAcls,.BlockPublicPolicy,.IgnorePublicAcls,.RestrictPublicBuckets] | all')" = "true" ]
check "Log bucket blocks all public access" $?

# Test 3: workgroup enforces the results bucket output location
WG_OUT=$(aws athena get-work-group --region "$REGION" --work-group "$WORKGROUP" \
  --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' --output text 2>/dev/null)
[ "$WG_OUT" = "s3://$RESULTS_BUCKET/" ]
check "Workgroup output location points at results bucket" $?

run_query() { # $1 = SQL; echoes QueryExecutionId, returns 0 on SUCCEEDED
  local qid state
  qid=$(aws athena start-query-execution --region "$REGION" --work-group "$WORKGROUP" \
    --query-string "$1" --query 'QueryExecutionId' --output text) || return 1
  for _ in $(seq 1 30); do
    state=$(aws athena get-query-execution --region "$REGION" --query-execution-id "$qid" \
      --query 'QueryExecution.Status.State' --output text)
    case "$state" in
      SUCCEEDED) echo "$qid"; return 0 ;;
      FAILED|CANCELLED)
        aws athena get-query-execution --region "$REGION" --query-execution-id "$qid" \
          --query 'QueryExecution.Status.StateChangeReason' --output text >&2
        return 1 ;;
    esac
    sleep 2
  done
  return 1
}

# Test 4: plain columns are queryable
run_query "SELECT eventname, eventsource FROM \"$DB\".\"$TABLE\" LIMIT 1" > /dev/null
check "Athena can query plain columns" $?

# Test 5: userIdentity struct fields parse correctly (JsonSerDe regression
# test - the legacy CloudTrailSerde fails here with HIVE_BAD_DATA)
run_query "SELECT useridentity.principalid, useridentity.sessioncontext.sessionissuer.arn, useridentity.onbehalfof.userid FROM \"$DB\".\"$TABLE\" LIMIT 1" > /dev/null
check "userIdentity struct fields parse (JsonSerDe)" $?

# Test 6: the exact query shape produced by the teamgetLogs lambda executes
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
DAY_AGO=$(date -u -v-24H +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S.000Z)
QID=$(run_query "SELECT eventid, eventname, eventsource, eventtime FROM \"$DB\".\"$TABLE\" WHERE from_iso8601_timestamp(eventtime) > from_iso8601_timestamp('$DAY_AGO') AND from_iso8601_timestamp(eventtime) < from_iso8601_timestamp('$NOW') AND lower(useridentity.principalid) LIKE '%:test-user%' AND useridentity.sessioncontext.sessionissuer.arn LIKE '%TEAM%' AND recipientaccountid = '000000000000'")
check "TEAM-shaped audit query executes" $?

# Test 7: query results land in the results bucket
if [ -n "${QID:-}" ]; then
  RESULT_LOC=$(aws athena get-query-execution --region "$REGION" --query-execution-id "$QID" \
    --query 'QueryExecution.ResultConfiguration.OutputLocation' --output text)
  case "$RESULT_LOC" in
    s3://$RESULTS_BUCKET/*) check "Query results written to results bucket" 0 ;;
    *) check "Query results written to results bucket" 1 ;;
  esac
else
  check "Query results written to results bucket" 1
fi

echo
echo "== Results: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
