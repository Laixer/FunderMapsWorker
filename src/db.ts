import postgres from "postgres";
import { env } from "./config.ts";

export const sql = postgres({
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
