import path from "node:path";
import { fileURLToPath } from "node:url";
import express from "express";
import helmet from "helmet";
import cors from "cors";
import { config } from "./config.js";
import { initPool } from "./db/pool.js";
import { runMigrations } from "./db/migrate.js";
import { healthRouter } from "./routes/health.js";
import { projectsRouter } from "./routes/projects.js";
import { tasksRouter } from "./routes/tasks.js";
import { attachmentsRouter } from "./routes/attachments.js";
import { uiRouter } from "./routes/ui.js";
import { notFoundHandler, errorHandler } from "./middleware/errorHandler.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function main() {
  await initPool();
  await runMigrations();

  const app = express();
  app.use(helmet());
  app.use(cors());
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));
  app.use(express.static(path.join(__dirname, "public")));

  app.set("view engine", "ejs");
  app.set("views", path.join(__dirname, "views"));

  app.use(healthRouter);
  app.use("/api/projects", projectsRouter);
  app.use("/api", tasksRouter);
  app.use("/api", attachmentsRouter);
  app.use(uiRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  app.listen(config.port, () => {
    console.log(`task-tracker-api listening on :${config.port}`);
  });
}

main().catch((err) => {
  console.error("Fatal startup error:", err);
  process.exit(1);
});
