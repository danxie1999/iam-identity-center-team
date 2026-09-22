// Minimal CDK app that deploys the amplify-export output as plain
// CloudFormation, using the official exported-backend construct for asset
// publication (Lambda zips, AppSync files, nested templates).
const cdk = require('aws-cdk-lib');
const { AmplifyExportedBackend } = require('@aws-amplify/cdk-exported-backend');

const app = new cdk.App();
const stack = new cdk.Stack(app, 'TEAM-BACKEND', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
new AmplifyExportedBackend(stack, 'TeamExportedBackend', {
  path: process.env.EXPORT_PATH,
  amplifyEnvironment: process.env.ENV_NAME || 'main',
});
app.synth();
