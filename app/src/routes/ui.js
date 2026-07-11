import { Router } from "express";
import multer from "multer";
import { randomUUID } from "node:crypto";
import { getPool } from "../db/pool.js";
import { asyncHandler } from "../middleware/asyncHandler.js";
import { uploadAttachment, presignAttachmentUrl, deleteAttachment } from "../aws/s3.js";

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 25 * 1024 * 1024 } });

export const uiRouter = Router();

uiRouter.get("/", (req, res) => res.redirect("/projects"));

uiRouter.get(
  "/projects",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query("SELECT * FROM projects ORDER BY created_at DESC");
    res.render("projects/index", { projects: rows, error: null });
  })
);

uiRouter.get("/projects/new", (req, res) => {
  res.render("projects/new", { error: null });
});

uiRouter.post(
  "/projects",
  asyncHandler(async (req, res) => {
    const { name, description } = req.body;
    if (!name) {
      return res.status(400).render("projects/new", { error: "Name is required" });
    }
    await getPool().query("INSERT INTO projects (id, name, description) VALUES ($1, $2, $3)", [
      randomUUID(),
      name,
      description || null,
    ]);
    res.redirect("/projects");
  })
);

uiRouter.get(
  "/projects/:id",
  asyncHandler(async (req, res) => {
    const { rows: projectRows } = await getPool().query("SELECT * FROM projects WHERE id = $1", [
      req.params.id,
    ]);
    if (projectRows.length === 0) {
      return res.status(404).render("projects/index", {
        projects: [],
        error: "Project not found",
      });
    }
    const { rows: tasks } = await getPool().query(
      "SELECT * FROM tasks WHERE project_id = $1 ORDER BY created_at DESC",
      [req.params.id]
    );
    res.render("projects/show", { project: projectRows[0], tasks, error: null });
  })
);

uiRouter.post(
  "/projects/:id/tasks",
  asyncHandler(async (req, res) => {
    const { title } = req.body;
    if (title) {
      await getPool().query("INSERT INTO tasks (id, project_id, title) VALUES ($1, $2, $3)", [
        randomUUID(),
        req.params.id,
        title,
      ]);
    }
    res.redirect(`/projects/${req.params.id}`);
  })
);

uiRouter.get(
  "/tasks/:id",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query("SELECT * FROM tasks WHERE id = $1", [req.params.id]);
    if (rows.length === 0) {
      return res.redirect("/projects");
    }
    const { rows: attachmentRows } = await getPool().query(
      "SELECT * FROM attachments WHERE task_id = $1 ORDER BY uploaded_at DESC",
      [req.params.id]
    );
    const attachments = await Promise.all(
      attachmentRows.map(async (a) => ({ ...a, download_url: await presignAttachmentUrl(a.s3_key) }))
    );
    res.render("tasks/show", { task: rows[0], attachments, error: null });
  })
);

uiRouter.post(
  "/tasks/:id/status",
  asyncHandler(async (req, res) => {
    const { status } = req.body;
    if (["todo", "in_progress", "done"].includes(status)) {
      await getPool().query(
        "UPDATE tasks SET status = $1, updated_at = now() WHERE id = $2",
        [status, req.params.id]
      );
    }
    res.redirect(`/tasks/${req.params.id}`);
  })
);

uiRouter.post(
  "/tasks/:id/attachments",
  upload.single("file"),
  asyncHandler(async (req, res) => {
    if (req.file) {
      const attachmentId = randomUUID();
      const s3Key = `tasks/${req.params.id}/${attachmentId}-${req.file.originalname}`;
      await uploadAttachment({ key: s3Key, body: req.file.buffer, contentType: req.file.mimetype });
      await getPool().query(
        `INSERT INTO attachments (id, task_id, s3_key, file_name, content_type, size_bytes)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [attachmentId, req.params.id, s3Key, req.file.originalname, req.file.mimetype, req.file.size]
      );
    }
    res.redirect(`/tasks/${req.params.id}`);
  })
);

uiRouter.post(
  "/tasks/:id/attachments/:attachmentId/delete",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query(
      "SELECT * FROM attachments WHERE id = $1 AND task_id = $2",
      [req.params.attachmentId, req.params.id]
    );
    if (rows.length > 0) {
      await deleteAttachment(rows[0].s3_key);
      await getPool().query("DELETE FROM attachments WHERE id = $1", [req.params.attachmentId]);
    }
    res.redirect(`/tasks/${req.params.id}`);
  })
);
