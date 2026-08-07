#!/usr/bin/env bash
# Deploys the TEAM Athena audit infrastructure:
#   1. CloudFormation stack (buckets, bucket policy, Glue db/table, workgroup)
#   2. Organization trail via CLI (see the note in athena-audit.yml for why
#      the trail cannot be managed by CloudFormation from a delegated admin)
#
# Run in the TEAM delegated administrator account. The account must already
# be the CloudTrail delegated administrator (deployment/init.sh does this).
#
#   ./athena-audit-deploy.sh <organization-id> <management-account-id> [region] [stack-name]
set -euo pipefail

ORG_ID="${1:?usage: athena-audit-deploy.sh <org-id> <mgmt-account-id> [region] [stack-name]}"
MGMT_ACCOUNT="${2:?usage: athena-audit-deploy.sh <org-id> <mgmt-account-id> [region] [stack-name]}"
REGION="${3:-us-east-1}"
STACK_NAME="${4:-TEAM-AUDIT-INFRA}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== Deploying stack $STACK_NAME =="
aws cloudformation deploy --region "$REGION" \
  --template-file "$SCRIPT_DIR/athena-audit.yml" \
  --stack-name "$STACK_NAME" \
  --parameter-overrides OrganizationId="$ORG_ID" ManagementAccountId="$MGMT_ACCOUNT" \
  --no-fail-on-empty-changeset

out() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text
}
LOG_BUCKET=$(out TrailLogBucketName)
TRAIL_NAME=$(out TrailName)
GLUE_TABLE_ARN=$(out GlueTableArn)

echo "== Creating organization trail $TRAIL_NAME =="
EXISTING=$(aws cloudtrail describe-trails --region "$REGION" --trail-name-list "$TRAIL_NAME" \
  --include-shadow-trails --query 'trailList[0].TrailARN' --output text 2>/dev/null || true)
if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
  echo "Trail already exists: $EXISTING"
  TRAIL_ARN="$EXISTING"
else
  TRAIL_ARN=$(aws cloudtrail create-trail --region "$REGION" \
    --name "$TRAIL_NAME" \
    --s3-bucket-name "$LOG_BUCKET" \
    --is-organization-trail \
    --is-multi-region-trail \
    --enable-log-file-validation \
    --query 'TrailARN' --output text)
  echo "Trail created: $TRAIL_ARN"
fi

aws cloudtrail start-logging --region "$REGION" --name "$TRAIL_ARN"
echo "Logging started"

echo
echo "== Done =="
echo "Set the following in deployment/parameters.sh to enable the Athena audit backend:"
echo "  CLOUDTRAIL_AUDIT_LOGS=$GLUE_TABLE_ARN"
echo "Then run update.sh (or push to the app repository) to redeploy TEAM."
