import { Router } from "express";
import multer from "multer";
import { randomUUID } from "node:crypto";
import { getPool } from "../db/pool.js";
import { asyncHandler } from "../middleware/asyncHandler.js";
import { uploadAttachment, presignAttachmentUrl, deleteAttachment } from "../aws/s3.js";

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 25 * 1024 * 1024 } });

// Mounted at /api
export const attachmentsRouter = Router();

attachmentsRouter.post(
  "/tasks/:id/attachments",
  upload.single("file"),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      return res.status(400).json({ error: "file is required" });
    }

    const attachmentId = randomUUID();
    const s3Key = `tasks/${req.params.id}/${attachmentId}-${req.file.originalname}`;

    await uploadAttachment({
      key: s3Key,
      body: req.file.buffer,
      contentType: req.file.mimetype,
    });

    const { rows } = await getPool().query(
      `INSERT INTO attachments (id, task_id, s3_key, file_name, content_type, size_bytes)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [attachmentId, req.params.id, s3Key, req.file.originalname, req.file.mimetype, req.file.size]
    );

    res.status(201).json(rows[0]);
  })
);

attachmentsRouter.get(
  "/tasks/:id/attachments",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query(
      "SELECT * FROM attachments WHERE task_id = $1 ORDER BY uploaded_at DESC",
      [req.params.id]
    );

    const withUrls = await Promise.all(
      rows.map(async (row) => ({
        ...row,
        download_url: await presignAttachmentUrl(row.s3_key),
      }))
    );

    res.json(withUrls);
  })
);

attachmentsRouter.delete(
  "/tasks/:id/attachments/:attachmentId",
  asyncHandler(async (req, res) => {
    const { rows } = await getPool().query(
      "SELECT * FROM attachments WHERE id = $1 AND task_id = $2",
      [req.params.attachmentId, req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: "Attachment not found" });
    }

    await deleteAttachment(rows[0].s3_key);
    await getPool().query("DELETE FROM attachments WHERE id = $1", [req.params.attachmentId]);

    res.status(204).send();
  })
);
