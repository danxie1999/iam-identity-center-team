# Copyright 2022 Amazon Web Services, Inc
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/usr/bin/env bash
set -xe

. "./parameters.sh"

# ---- Deployment-mode selection & partition fail-fast (all optional; unset = current behaviour) ----
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-amplify}"
case "$DEPLOYMENT_MODE" in
  amplify)   TEMPLATE_FILE=template.yml; EXTRA_OVERRIDES="" ;;
  codebuild) TEMPLATE_FILE=template-codebuild.yml
             EXTRA_OVERRIDES="frontendMode=${FRONTEND_MODE:-cloudfront} uiDomainCertificateArn=${UI_DOMAIN_CERTIFICATE_ARN:-}" ;;
  *) echo "ERROR: DEPLOYMENT_MODE must be 'amplify' or 'codebuild' (got '$DEPLOYMENT_MODE')"; exit 1 ;;
esac
if [[ "$REGION" == cn-* && "$DEPLOYMENT_MODE" == "amplify" ]]; then
  echo "ERROR: Amplify Hosting is not available in the China (aws-cn) regions."
  echo "       Set DEPLOYMENT_MODE=codebuild in parameters.sh."
  exit 1
fi
if [[ "$DEPLOYMENT_MODE" == "codebuild" && ! -z "$UI_DOMAIN" && -z "$UI_DOMAIN_CERTIFICATE_ARN" ]]; then
  echo "ERROR: UI_DOMAIN with DEPLOYMENT_MODE=codebuild requires UI_DOMAIN_CERTIFICATE_ARN"
  echo "       (an ACM certificate in the deployment region; Amplify Hosting manages"
  echo "       certificates automatically, the CodeBuild rail does not)."
  exit 1
fi


if [ -z "$TEAM_ACCOUNT" ]; then 
  export AWS_PROFILE=$ORG_MASTER_PROFILE
else 
  export AWS_PROFILE=$TEAM_ACCOUNT_PROFILE
fi

cd ..

if [ -z "$SECRET_NAME" ]; then
  aws codecommit create-repository --region $REGION --repository-name team-idc-app --repository-description "Temporary Elevated Access Management (TEAM) Application"
  git remote remove origin
  git remote add origin codecommit::$REGION://team-idc-app
  git push origin main

  cd ./deployment
  if [[ ! -z "$TAGS" ]]; then
    if [[ ! -z "$UI_DOMAIN" ]]; then
      aws cloudformation deploy --region $REGION --template-file $TEMPLATE_FILE \
        --stack-name TEAM-IDC-APP \
        --parameter-overrides \
          Login=$IDC_LOGIN_URL \
          CloudTrailAuditLogs=$CLOUDTRAIL_AUDIT_LOGS \
          teamAdminGroup="$TEAM_ADMIN_GROUP" \
          teamAuditGroup="$TEAM_AUDITOR_GROUP" \
          tags="$TAGS" \
          teamAccount="$TEAM_ACCOUNT" \
          cacheTTL=$CACHE_TTL \
          customAmplifyDomain="$UI_DOMAIN" \
        --tags $TAGS \
        $EXTRA_OVERRIDES --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
    else
      aws cloudformation deploy --region $REGION --template-file $TEMPLATE_FILE \
        --stack-name TEAM-IDC-APP \
        --parameter-overrides \
          Login=$IDC_LOGIN_URL \
          CloudTrailAuditLogs=$CLOUDTRAIL_AUDIT_LOGS \
          teamAdminGroup="$TEAM_ADMIN_GROUP" \
          teamAuditGroup="$TEAM_AUDITOR_GROUP" \
          tags="$TAGS" \
          teamAccount="$TEAM_ACCOUNT" \
          cacheTTL=$CACHE_TTL \
        --tags $TAGS \
        $EXTRA_OVERRIDES --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
    fi
  else
    if [[ ! -z "$UI_DOMAIN" ]]; then
      aws cloudformation deploy --region $REGION --template-file $TEMPLATE_FILE \
        --stack-name TEAM-IDC-APP \
        --parameter-overrides \
          Login=$IDC_LOGIN_URL \
          CloudTrailAuditLogs=$CLOUDTRAIL_AUDIT_LOGS \
          teamAdminGroup="$TEAM_ADMIN_GROUP" \
          teamAuditGroup="$TEAM_AUDITOR_GROUP" \
          teamAccount="$TEAM_ACCOUNT" \
          tags="$TAGS" \
          customAmplifyDomain="$UI_DOMAIN" \
          cacheTTL=$CACHE_TTL \
        $EXTRA_OVERRIDES --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
    else
      aws cloudformation deploy --region $REGION --template-file $TEMPLATE_FILE \
        --stack-name TEAM-IDC-APP \
        --parameter-overrides \
          Login=$IDC_LOGIN_URL \
          CloudTrailAuditLogs=$CLOUDTRAIL_AUDIT_LOGS \
          teamAdminGroup="$TEAM_ADMIN_GROUP" \
          teamAuditGroup="$TEAM_AUDITOR_GROUP" \
          teamAccount="$TEAM_ACCOUNT" \
          cacheTTL=$CACHE_TTL \
        $EXTRA_OVERRIDES --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
    fi
  fi
else
  cd ./deployment
  if [[ ! -z "$TAGS" ]]; then
    if [[ ! -z "$UI_DOMAIN" ]]; then
      aws cloudformation deploy --region $REGION --template-file $TEMPLATE_FILE \
        --stack-name TEAM-IDC-APP \
        --parameter-overrides \
          Login=$IDC_LOGIN_URL \
          CloudTrailAuditLogs=$CLOUDTRAIL_AUDIT_LOGS \
          teamAdminGroup="$TEAM_ADMIN_GROUP" \
          teamAuditGroup="$TEAM_AUDITOR_GROUP" \
          tags="$TAGS" \
          teamAccount="$TEAM_ACCOUNT" \
          customAmplifyDomain="$UI_DOMAIN" \
          cacheTTL=$CACHE_TTL \
          customRepository="Yes" \
          customRepositorySecretName="$SECRET_NAME" \
        --tags $TAGS \
        $EXTRA_OVERRIDES --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
    else
      aws cloudformation deploy --region $REGION --template-file $TEMPLATE_FILE \
        --stack-name TEAM-IDC-APP \
        --parameter-overrides \
          Login=$IDC_LOGIN_URL \
          CloudTrailAuditLogs=$CLOUDTRAIL_AUDIT_LOGS \
          teamAdminGroup="$TEAM_ADMIN_GROUP" \
          teamAuditGroup="$TEAM_AUDITOR_GROUP" \
          tags="$TAGS" \
          teamAccount="$TEAM_ACCOUNT" \
          cacheTTL=$CACHE_TTL \
          customRepository="Yes" \
          customRepositorySecretName="$SECRET_NAME" \
        --tags $TAGS \
        $EXTRA_OVERRIDES --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
    fi
  else
    if [[ ! -z "$UI_DOMAIN" ]]; then
      aws cloudformation deploy --region $REGION --template-file $TEMPLATE_FILE \
        --stack-name TEAM-IDC-APP \
        --parameter-overrides \
          Login=$IDC_LOGIN_URL \
          CloudTrailAuditLogs=$CLOUDTRAIL_AUDIT_LOGS \
          teamAdminGroup="$TEAM_ADMIN_GROUP" \
          teamAuditGroup="$TEAM_AUDITOR_GROUP" \
          teamAccount="$TEAM_ACCOUNT" \
          tags="$TAGS" \
          customAmplifyDomain="$UI_DOMAIN" \
          cacheTTL=$CACHE_TTL \
          customRepository="Yes" \
          customRepositorySecretName="$SECRET_NAME" \
        $EXTRA_OVERRIDES --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
    else
      aws cloudformation deploy --region $REGION --template-file $TEMPLATE_FILE \
        --stack-name TEAM-IDC-APP \
        --parameter-overrides \
          Login=$IDC_LOGIN_URL \
          CloudTrailAuditLogs=$CLOUDTRAIL_AUDIT_LOGS \
          teamAdminGroup="$TEAM_ADMIN_GROUP" \
          teamAuditGroup="$TEAM_AUDITOR_GROUP" \
          teamAccount="$TEAM_ACCOUNT" \
          cacheTTL=$CACHE_TTL \
          customRepository="Yes" \
          customRepositorySecretName="$SECRET_NAME" \
        $EXTRA_OVERRIDES --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
    fi
  fi
fi