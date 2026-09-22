#!/usr/bin/env python3
"""Prepare a clean checkout for headless `amplify export` (no Amplify Hosting).

The Amplify CLI requires project/environment state that only exists after
`amplify init`. On the CodeBuild deployment rail there is no initialized
environment, so this script synthesizes the minimal state from what is already
in the repository (backend-config.json) plus environment variables, letting
`amplify export` run headlessly with zero cloud calls.

Also normalizes two source-level issues that only surface on the export path:
- wires authRoleName/unauthRoleName (declared by the api stack, created by the
  export root stack) into api parameters
- (aws-cn) nothing partition-specific here; generated-output normalization is
  handled by normalize-partition.py after export

Environment variables (all provided by the CodeBuild project environment):
  TEAM_ACCOUNT   deployment account id
  AWS_REGION     deployment region (cn-* selects the aws-cn partition)
  ENV_NAME       amplify environment name (default: main)
"""
import json
import os
import shutil

ROOT = os.getcwd()
ACCOUNT = os.environ["TEAM_ACCOUNT"]
REGION = os.environ.get("AWS_REGION", "us-east-1")
ENV = os.environ.get("ENV_NAME", "main")
PARTITION = "aws-cn" if REGION.startswith("cn-") else "aws"
# Amplify-convention names: the exported-backend construct derives resource
# names from these; non-conventional values produce colliding derivations.
PROJECT = "teamidcapp"
PREFIX = f"amplify-{PROJECT}-{ENV}-00000"

os.makedirs("amplify/.config", exist_ok=True)
json.dump({"projectPath": ROOT, "defaultEditor": "code", "envName": ENV},
          open("amplify/.config/local-env-info.json", "w"), indent=2)
json.dump({
    "projectName": PROJECT, "version": "3.1", "frontend": "javascript",
    "javascript": {"framework": "react", "config": {
        "SourceDir": "src", "DistributionDir": "build",
        "BuildCommand": "npm run-script build", "StartCommand": "npm run-script start"}},
    "providers": ["awscloudformation"],
}, open("amplify/.config/project-config.json", "w"), indent=2)
json.dump({ENV: {"awscloudformation": {
    "AuthRoleName": f"{PREFIX}-authRole",
    "UnauthRoleArn": f"arn:{PARTITION}:iam::{ACCOUNT}:role/{PREFIX}-unauthRole",
    "AuthRoleArn": f"arn:{PARTITION}:iam::{ACCOUNT}:role/{PREFIX}-authRole",
    "Region": REGION,
    "DeploymentBucketName": os.environ.get("DEPLOY_BUCKET", f"{PREFIX}-deployment"),
    "UnauthRoleName": f"{PREFIX}-unauthRole",
    "StackName": PREFIX,
    "StackId": f"arn:{PARTITION}:cloudformation:{REGION}:{ACCOUNT}:stack/{PREFIX}/00000000-0000-0000-0000-000000000000",
    "AmplifyAppId": "headlessexport",
}}}, open("amplify/team-provider-info.json", "w"), indent=2)

bc = json.load(open("amplify/backend/backend-config.json"))
meta = {"providers": {"awscloudformation":
        json.load(open("amplify/team-provider-info.json"))[ENV]["awscloudformation"]}}
for cat, resources in bc.items():
    if cat in ("parameters", "hosting"):  # not exportable categories
        continue
    meta[cat] = {}
    for name, cfg in resources.items():
        entry = dict(cfg)
        entry.setdefault("providerPlugin", "awscloudformation")
        meta[cat][name] = entry
json.dump(meta, open("amplify/backend/amplify-meta.json", "w"), indent=2)
os.makedirs("amplify/#current-cloud-backend", exist_ok=True)
shutil.copy("amplify/backend/amplify-meta.json",
            "amplify/#current-cloud-backend/amplify-meta.json")
shutil.copy("amplify/backend/backend-config.json",
            "amplify/#current-cloud-backend/backend-config.json")

# The api stack declares authRoleName/unauthRoleName (no defaults); the export
# manifest does not carry them. Wire the names created by the export root stack.
pj = "amplify/backend/api/team/parameters.json"
p = json.load(open(pj))
p["authRoleName"] = f"{PREFIX}-authRole"
p["unauthRoleName"] = f"{PREFIX}-unauthRole"
json.dump(p, open(pj, "w"), indent=2)

print(f"headless export state synthesized: account={ACCOUNT} region={REGION} env={ENV}")
