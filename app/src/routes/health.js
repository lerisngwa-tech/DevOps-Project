import { Router } from "express";
import { getPool } from "../db/pool.js";

export const healthRouter = Router();

healthRouter.get("/healthz", (req, res) => {
  res.status(200).json({ status: "ok" });
});

// Fails closed (503) rather than throwing, so a transient DB/Secrets Manager
// outage marks the pod not-ready instead of crash-looping.
healthRouter.get("/readyz", async (req, res) => {
  try {
    await getPool().query("SELECT 1");
    res.status(200).json({ status: "ready" });
  } catch (err) {
    console.error("Readiness check failed:", err.message);
    res.status(503).json({ status: "not ready" });
  }
});
