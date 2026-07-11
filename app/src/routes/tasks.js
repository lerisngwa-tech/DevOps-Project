import { Router } from "express";
import { randomUUID } from "node:crypto";
import { getPool } from "../db/pool.js";
import { asyncHandler } from "../middleware/asyncHandler.js";

// Mounted at /api — routes below are nested under /projects/:projectId/tasks
// for listing/creating, and flat /tasks/:id for read/update/delete.
export const tasksRouter = Router();

tasksRouter.get(
  "/projects/:projectId/tasks",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query(
      "SELECT * FROM tasks WHERE project_id = $1 ORDER BY created_at DESC",
      [req.params.projectId]
    );
    res.json(rows);
  })
);

tasksRouter.post(
  "/projects/:projectId/tasks",
  asyncHandler(async (req, res) => {
    const { title, description, assignee_id } = req.body;
    if (!title) {
      return res.status(400).json({ error: "title is required" });
    }
    const id = randomUUID();
    const { rows } = await getPool().query(
      "INSERT INTO tasks (id, project_id, title, description, assignee_id) VALUES ($1, $2, $3, $4, $5) RETURNING *",
      [id, req.params.projectId, title, description ?? null, assignee_id ?? null]
    );
    res.status(201).json(rows[0]);
  })
);

tasksRouter.get(
  "/tasks/:id",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query("SELECT * FROM tasks WHERE id = $1", [
      req.params.id,
    ]);
    if (rows.length === 0) {
      return res.status(404).json({ error: "Task not found" });
    }
    res.json(rows[0]);
  })
);

tasksRouter.put(
  "/tasks/:id",
  asyncHandler(async (req, res) => {
    const { title, description, status, assignee_id } = req.body;
    const { rows } = await getPool().query(
      `UPDATE tasks SET
         title = COALESCE($1, title),
         description = COALESCE($2, description),
         status = COALESCE($3, status),
         assignee_id = COALESCE($4, assignee_id),
         updated_at = now()
       WHERE id = $5
       RETURNING *`,
      [title ?? null, description ?? null, status ?? null, assignee_id ?? null, req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: "Task not found" });
    }
    res.json(rows[0]);
  })
);

tasksRouter.delete(
  "/tasks/:id",
  asyncHandler(async (req, res) => {
    const { rowCount } = await getPool().query("DELETE FROM tasks WHERE id = $1", [
      req.params.id,
    ]);
    if (rowCount === 0) {
      return res.status(404).json({ error: "Task not found" });
    }
    res.status(204).send();
  })
);
