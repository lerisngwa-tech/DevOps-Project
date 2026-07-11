import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { getPool } from "./pool.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export async function runMigrations() {
  const schema = await readFile(path.join(__dirname, "schema.sql"), "utf-8");
  await getPool().query(schema);
}
