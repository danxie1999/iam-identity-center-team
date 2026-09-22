# CodeBuild deployment mode

`DEPLOYMENT_MODE=codebuild` deploys TEAM **without Amplify Hosting**, for
partitions and environments where it is unavailable or restricted — the AWS
China regions (`aws-cn`), AWS GovCloud (`aws-us-gov`), and enterprises that do
not permit Amplify Hosting.

The operator experience is identical to the default mode: fill
`parameters.sh`, run `init.sh`, run `deploy.sh`. One variable selects the
rail.

## How it differs from the default (Amplify) mode

| | `amplify` (default) | `codebuild` |
|---|---|---|
| Installer stack | `template.yml` (`AWS::Amplify::App` + `Branch`) | `template-codebuild.yml` (`AWS::CodeBuild::Project`) |
| Configuration | Amplify branch environment variables | CodeBuild environment variables — **same names** (`SSO_LOGIN`, `TEAM_ACCOUNT`, …) |
| Backend install | `amplifyPush` inside the Amplify build | `amplify export` at build time → deployed as plain CloudFormation (assets published via `@aws-amplify/cdk-exported-backend`) |
| Frontend hosting | Amplify Hosting | `frontend-hosting.yml`: S3 + CloudFront (default) or S3 + Lambda/HTTP API (`FRONTEND_MODE=apigateway`) |
| Rebuild on push | Amplify branch auto-build | EventBridge rule on the CodeCommit repository |

The `amplify/` directory remains the **single source** for both rails: no
flattened or hand-maintained copy of the backend is ever committed. Two small
helper scripts run inside the build:

- `deployment/headless-export-prep.py` — synthesizes the Amplify project
  state a clean checkout lacks, so `amplify export` runs headlessly
- `deployment/normalize-partition.py` — rewrites the `arn:aws:` prefixes the
  GraphQL transformer generates into the deployment partition (a no-op in
  the `aws` partition)

## Usage

```bash
cd deployment
cp parameters-template.sh parameters.sh
# fill the standard variables, then:
#   DEPLOYMENT_MODE=codebuild
#   FRONTEND_MODE=apigateway     # optional; default cloudfront
./init.sh
./deploy.sh
```

`deploy.sh` fails fast on impossible combinations (for example
`DEPLOYMENT_MODE=amplify` in a `cn-*` region) before any AWS call is made.

## Current limitations

- `UI_DOMAIN` (Amplify custom domain) is not supported in this mode —
  configure a custom domain on the frontend hosting stack instead
  (`DomainName`/`AcmCertificateArn` parameters, cloudfront mode).
- Auth: the default Cognito auth category requires Cognito User Pools, which
  do not exist in the `aws-cn` regions. China deployments additionally
  require the `lambda-saml` auth provider (separate option; see the auth
  provider documentation when available).
