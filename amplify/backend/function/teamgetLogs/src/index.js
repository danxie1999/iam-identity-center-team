//  © 2023 Amazon Web Services, Inc. or its affiliates. All Rights Reserved.
//  This AWS Content is provided subject to the terms of the AWS Customer Agreement available at
//  http: // aws.amazon.com/agreement or other written agreement between Customer and either
//  Amazon Web Services, Inc. or Amazon Web Services EMEA SARL or both.

/* Amplify Params - DO NOT EDIT
	API_TEAM_GRAPHQLAPIENDPOINTOUTPUT
	API_AWSPIM_GRAPHQLAPIIDOUTPUT
	ENV
	REGION
Amplify Params - DO NOT EDIT */
import crypto from '@aws-crypto/sha256-js';
import { defaultProvider } from '@aws-sdk/credential-provider-node';
import { SignatureV4 } from '@aws-sdk/signature-v4';
import { HttpRequest } from '@aws-sdk/protocol-http';
import { default as fetch, Request } from 'node-fetch';

import {
  CloudTrailClient,
  StartQueryCommand,
  DescribeQueryCommand,
} from "@aws-sdk/client-cloudtrail"

import {
  AthenaClient,
  StartQueryExecutionCommand,
  GetQueryExecutionCommand,
} from "@aws-sdk/client-athena"

const { Sha256 } = crypto;
const REGION = process.env.REGION;

// Audit log backend mode:
// - CloudTrail Lake (default): EVENT_DATA_STORE is an EventDataStore ARN or ID
// - CloudTrail + Athena: EVENT_DATA_STORE is a Glue table ARN
//   (arn:aws:glue:<region>:<account>:table/<database>/<table>) pointing to an
//   Athena table over CloudTrail logs delivered to S3 by a (organization) trail.
//   Optional env vars: ATHENA_WORKGROUP (default: primary), ATHENA_OUTPUT_LOCATION
//   (s3://... for query results; falls back to the workgroup default location)
const EVENT_DATA_STORE_RAW = process.env.EVENT_DATA_STORE;
const isAthenaMode = /^arn:aws[a-zA-Z-]*:glue:/.test(EVENT_DATA_STORE_RAW);
const EventDataStore = EVENT_DATA_STORE_RAW.split("/").pop();
const GRAPHQL_ENDPOINT = process.env.API_TEAM_GRAPHQLAPIENDPOINTOUTPUT;
const ATHENA_WORKGROUP = process.env.ATHENA_WORKGROUP || "primary";
const ATHENA_OUTPUT_LOCATION = process.env.ATHENA_OUTPUT_LOCATION;

// const {
//   CloudTrailClient,
//   StartQueryCommand,
//   DescribeQueryCommand,
// } = require("@aws-sdk/client-cloudtrail");

const client = new CloudTrailClient({ region: REGION });
const athenaClient = new AthenaClient({ region: REGION });

// Parse database and table name from a Glue table ARN
// arn:aws:glue:<region>:<account>:table/<database>/<table>
const parseGlueTableArn = (arn) => {
  const parts = arn.split(":table/").pop().split("/");
  return { database: parts[0], table: parts[1] };
};

const query = /* GraphQL */ `
  mutation UpdateSessions(
    $input: UpdateSessionsInput!
    $condition: ModelSessionsConditionInput
  ) {
    updateSessions(input: $input, condition: $condition) {
      id
      startTime
      endTime
      username
      accountId
      role
      approver_ids
      queryId
      createdAt
      updatedAt
      owner
    }
  }
`;

/**
 * @type {import('@types/aws-lambda').APIGatewayProxyHandler}
 */

const updateItem = async (id, queryId) => {
  const variables = {
    input: {
      id: id,
      queryId: queryId
    } 
  }

  const endpoint = new URL(GRAPHQL_ENDPOINT);

  const signer = new SignatureV4({
    credentials: defaultProvider(),
    region: REGION,
    service: 'appsync',
    sha256: Sha256
  });

  const requestToBeSigned = new HttpRequest({
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      host: endpoint.host
    },
    hostname: endpoint.host,
    body: JSON.stringify({ query, variables }),
    path: endpoint.pathname
  });

  const signed = await signer.sign(requestToBeSigned);
  const request = new Request(endpoint, signed);

  let statusCode = 200;
  let body;
  let response;

  try {
    response = await fetch(request);
    body = await response.json();
    console.log(body);
    if (body.errors) statusCode = 400;
  } catch (error) {
    statusCode = 400;
    body = {
      errors: [
        {
          status: response.status,
          message: error.message,
          stack: error.stack
        }
      ]
    };
  }

  return {
    statusCode,
    body: JSON.stringify(body)
  };
};


// Returns a normalized status: "FINISHED" | "FAILED" | <in-flight status>
const get_query_status = async (queryId) => {
  try {
    if (isAthenaMode) {
      const command = new GetQueryExecutionCommand({ QueryExecutionId: queryId });
      const response = await athenaClient.send(command);
      const state = response.QueryExecution.Status.State;
      if (state === "SUCCEEDED") return "FINISHED";
      if (state === "FAILED" || state === "CANCELLED") {
        console.log("Athena query failed:", response.QueryExecution.Status.StateChangeReason);
        return "FAILED";
      }
      return state; // QUEUED | RUNNING
    }
    const input = {
      EventDataStore: EventDataStore,
      QueryId: queryId,
    };
    const command = new DescribeQueryCommand(input);
    const response = await client.send(command);
    const status = response.QueryStatus;
    if (status === "FAILED" || status === "CANCELLED" || status === "TIMED_OUT") {
      console.log("CloudTrail Lake query failed:", response.ErrorMessage);
      return "FAILED";
    }
    return status;
  } catch (err) {
    console.log("Error", err);
    return "FAILED";
  }
};

const start_query = async (event) => {
  const startTime = event["startTime"]["S"];
  const endTime = event["endTime"]["S"];
  const  username = event["username"]["S"].replace('idc_', '');
  const accountId = event["accountId"]["S"];
  const role = event["role"]["S"];
  try {
    if (isAthenaMode) {
      const { database, table } = parseGlueTableArn(EVENT_DATA_STORE_RAW);
      // Standard CloudTrail-on-S3 Athena table schema: lowercase columns,
      // eventtime is an ISO8601 string (e.g. 2026-08-06T11:24:05Z)
      const startIso = new Date(startTime).toISOString();
      const endIso = new Date(endTime).toISOString();
      const queryString = `SELECT eventid, eventname, eventsource, eventtime FROM "${database}"."${table}" WHERE from_iso8601_timestamp(eventtime) > from_iso8601_timestamp('${startIso}') AND from_iso8601_timestamp(eventtime) < from_iso8601_timestamp('${endIso}') AND lower(useridentity.principalid) LIKE '%:${username}%' AND useridentity.sessioncontext.sessionissuer.arn LIKE '%${role}%' AND recipientaccountid = '${accountId}'`;
      const input = {
        QueryString: queryString,
        QueryExecutionContext: { Database: database },
        WorkGroup: ATHENA_WORKGROUP,
      };
      if (ATHENA_OUTPUT_LOCATION) {
        input.ResultConfiguration = { OutputLocation: ATHENA_OUTPUT_LOCATION };
      }
      const command = new StartQueryExecutionCommand(input);
      const response = await athenaClient.send(command);
      return response.QueryExecutionId;
    }
    const input = {
      QueryStatement: `SELECT eventID, eventName, eventSource, eventTime FROM ${EventDataStore} WHERE eventTime > '${startTime}' AND eventTime < '${endTime}' AND lower(useridentity.principalId) LIKE '%:${username}%' AND useridentity.sessionContext.sessionIssuer.arn LIKE '%${role}%' AND recipientAccountId='${accountId}'`,
    };
    const command = new StartQueryCommand(input);
    const response = await client.send(command);
    return response.QueryId;
  } catch (err) {
    console.log("Error", err);
  }
};

export const handler = async (event) => {
  let data = event["Records"].pop()
  data = data["dynamodb"]["NewImage"]
  const id = data["id"]["S"]
  console.log("Event", data);
  console.log("Audit backend mode:", isAthenaMode ? "athena" : "cloudtrail-lake");
  const queryId = await start_query(data);
  if (!queryId) {
    console.log("Failed to start audit log query");
    return;
  }
  let status = await get_query_status(queryId);
  while (status) {
    console.log(status);
    if (status === "FINISHED") {
      console.log("query Finished - queryId:", queryId );
      const response = await updateItem (id, queryId);
      return response;
    }
    if (status === "FAILED") {
      console.log("query failed - queryId:", queryId);
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
    status = await get_query_status(queryId);
  }
};