//  © 2023 Amazon Web Services, Inc. or its affiliates. All Rights Reserved.
//  This AWS Content is provided subject to the terms of the AWS Customer Agreement available at
//  http: // aws.amazon.com/agreement or other written agreement between Customer and either
//  Amazon Web Services, Inc. or Amazon Web Services EMEA SARL or both.

// Audit log backend mode:
// - CloudTrail Lake (default): EVENT_DATA_STORE is an EventDataStore ARN or ID
// - CloudTrail + Athena: EVENT_DATA_STORE is a Glue table ARN
//   (arn:aws:glue:<region>:<account>:table/<database>/<table>)
const EVENT_DATA_STORE_RAW = process.env.EVENT_DATA_STORE;
const isAthenaMode = /^arn:aws[a-zA-Z-]*:glue:/.test(EVENT_DATA_STORE_RAW);
const EventDataStore = EVENT_DATA_STORE_RAW.split("/").pop();
const REGION = process.env.REGION;
const {
    CloudTrailClient,
    paginateGetQueryResults,
  } = require("@aws-sdk/client-cloudtrail");
const {
    AthenaClient,
    paginateGetQueryResults: paginateAthenaGetQueryResults,
  } = require("@aws-sdk/client-athena");
const client = new CloudTrailClient({ region: REGION });
const athenaClient = new AthenaClient({ region: REGION });

// Map lowercase Athena column names to the camelCase keys expected by the frontend
const COLUMN_MAP = {
  eventid: "eventID",
  eventname: "eventName",
  eventsource: "eventSource",
  eventtime: "eventTime",
};

const get_athena_query = async (queryId) => {
  try {
    const output = [];
    const input = { QueryExecutionId: queryId };
    const paginatorConfig = { client: athenaClient };
    const paginator = paginateAthenaGetQueryResults(paginatorConfig, input);
    let header = null;
    for await (const page of paginator) {
      for (const row of page.ResultSet.Rows) {
        const values = row.Data.map((d) => (d && d.VarCharValue) || "");
        if (!header) {
          // First row of an Athena SELECT result is the header row
          header = values.map((v) => COLUMN_MAP[v.toLowerCase()] || v);
          continue;
        }
        const logs = {};
        header.forEach((k, i) => {
          logs[k] = values[i];
        });
        output.push(logs);
      }
    }
    console.log(output);
    return output;
  } catch (err) {
    console.log("Error", err);
  }
};

const get_query = async (queryId) => {
try {
    const output = [];
    const input = {
    EventDataStore: EventDataStore,
    QueryId: queryId,
    };
    const paginatorConfig = {
    client: new CloudTrailClient({ region: REGION }),
    };
    const paginator = paginateGetQueryResults(paginatorConfig, input);
    for await (const page of paginator) {
    // page contains a single paginated output.
    for (const data of page.QueryResultRows) {
        const logs = {};
        for (const log of data) {
        for (const [k, v] of Object.entries(log)) {
            logs[k] = v;
        }
        }
        output.push(logs);
    }
    }
    console.log(output);
    return output;
} catch (err) {
    console.log("Error", err);
}
};

exports.handler = async (event) => {
    const queryId = event["arguments"]["queryId"]
    return isAthenaMode ? get_athena_query(queryId) : get_query(queryId);
};
