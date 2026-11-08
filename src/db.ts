import postgres from "postgres";
import { env } from "./config.ts";

export const sql = postgres({
  // infer: true keeps the parameter types of postgres v3 (a Date is a timestamptz, a boolean a boolean), as the API
  // does since its move to v4 on 2026-11-02. Without it v4 leaves them to the server, and a Date where the query does
  // not decide its type becomes an error at run time, which no test here would catch.
  infer: true,
  host: env.FUNDERMAPS_DATABASE_HOST,
  port: env.FUNDERMAPS_DATABASE_PORT,
  database: env.FUNDERMAPS_DATABASE_NAME,
  username: env.FUNDERMAPS_DATABASE_USER,
  password: env.FUNDERMAPS_DATABASE_PASSWORD,
  ssl: "prefer",
  connection: {
    application_name: "fundermaps-worker",
  },
  max: 10,
  idle_timeout: 30,
  connect_timeout: 10,
  keep_alive: 60,
  types: {
    numeric: {
      to: 1700,
      from: [1700],
      serialize: (x: number) => String(x),
      parse: (x: string) => Number(x),
    },
    bigint: {
      to: 20,
      from: [20],
      serialize: (x: number) => String(x),
      parse: (x: string) => Number(x),
    },
  },
});

export function pgConnectionString(): string {
  return `PG:dbname='${env.FUNDERMAPS_DATABASE_NAME}' host='${env.FUNDERMAPS_DATABASE_HOST}' port='${env.FUNDERMAPS_DATABASE_PORT}' user='${env.FUNDERMAPS_DATABASE_USER}' password='${env.FUNDERMAPS_DATABASE_PASSWORD}' application_name='fundermaps-worker'`;
}
