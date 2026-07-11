import { Router } from "express";
import { randomUUID } from "node:crypto";
import { getPool } from "../db/pool.js";
import { asyncHandler } from "../middleware/asyncHandler.js";

export const projectsRouter = Router();

projectsRouter.get(
  "/",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query(
      "SELECT * FROM projects ORDER BY created_at DESC"
    );
    res.json(rows);
  })
);

projectsRouter.post(
  "/",
  asyncHandler(async (req, res) => {
    const { name, description, created_by } = req.body;
    if (!name) {
      return res.status(400).json({ error: "name is required" });
    }
    const id = randomUUID();
    const { rows } = await getPool().query(
      "INSERT INTO projects (id, name, description, created_by) VALUES ($1, $2, $3, $4) RETURNING *",
      [id, name, description ?? null, created_by ?? null]
    );
    res.status(201).json(rows[0]);
  })
);

projectsRouter.get(
  "/:id",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query("SELECT * FROM projects WHERE id = $1", [
      req.params.id,
    ]);
    if (rows.length === 0) {
      return res.status(404).json({ error: "Project not found" });
    }
    res.json(rows[0]);
  })
);

projectsRouter.put(
  "/:id",
  asyncHandler(async (req, res) => {
    const { name, description } = req.body;
    const { rows } = await getPool().query(
      "UPDATE projects SET name = COALESCE($1, name), description = COALESCE($2, description) WHERE id = $3 RETURNING *",
      [name ?? null, description ?? null, req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: "Project not found" });
    }
    res.json(rows[0]);
  })
);

projectsRouter.delete(
  "/:id",
  asyncHandler(async (req, res) => {
    const { rowCount } = await getPool().query("DELETE FROM projects WHERE id = $1", [
      req.params.id,
    ]);
    if (rowCount === 0) {
      return res.status(404).json({ error: "Project not found" });
    }
    res.status(204).send();
  })
);
