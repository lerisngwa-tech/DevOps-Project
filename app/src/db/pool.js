import pg from "pg";
import { getDbCredentials } from "../aws/secrets.js";

const { Pool } = pg;

let pool;

export async function initPool() {
  const creds = await getDbCredentials();

  pool = new Pool({
    host: creds.host,
    port: creds.port,
    database: creds.dbname,
    user: creds.username,
    password: creds.password,
    max: 10,
    ssl: { rejectUnauthorized: false },
  });

  return pool;
}

export function getPool() {
  if (!pool) {
    throw new Error("Database pool not initialized — call initPool() at startup first");
  }
  return pool;
}
