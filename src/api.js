import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import express from "express";
import { loginUser, scriptLoginWithPassword, scriptLoginWithSavedKey, validateToken } from "./auth.js";
import { prisma } from "./db.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function createApi() {
  const app = express();

  // Raw UniversalAdmin client script for HttpGet + loadstring (rejoin auto-reexec).
  // Tries public/ first, then repo-root UniversalAdmin.lua when the full monorepo is deployed.
  app.get("/UniversalAdmin.lua", (_req, res) => {
    const candidates = [
      path.join(__dirname, "../public/UniversalAdmin.lua"),
      path.join(__dirname, "../../UniversalAdmin.lua"),
    ];
    for (const p of candidates) {
      try {
        if (fs.existsSync(p)) {
          res.type("text/plain; charset=utf-8");
          return res.send(fs.readFileSync(p, "utf8"));
        }
      } catch {
        // try next
      }
    }
    res
      .status(404)
      .type("text/plain")
      .send(
        "-- UniversalAdmin.lua not found on server. Add it to public/UniversalAdmin.lua or deploy the repo with UniversalAdmin.lua next to discord-key-auth/.\n"
      );
  });

  app.use(express.static(path.join(__dirname, "../public")));
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({ ok: true });
  });

  app.post("/auth/login", async (req, res) => {
    try {
      const { username, password } = req.body || {};
      if (!username || !password) {
        return res.status(400).json({ ok: false, error: "username and password required" });
      }
      const result = await loginUser({ username, password });
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  app.post("/auth/script-login", async (req, res) => {
    try {
      const { username, password } = req.body || {};
      if (!username || !password) {
        return res.status(400).json({ ok: false, error: "username and password required" });
      }
      const result = await scriptLoginWithPassword({ username, password });
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  app.post("/auth/script-login-key", async (req, res) => {
    try {
      const { username, key } = req.body || {};
      if (!username || !key) {
        return res.status(400).json({ ok: false, error: "username and key required" });
      }
      const result = await scriptLoginWithSavedKey({ username, keyCode: key });
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  app.post("/auth/validate", (req, res) => {
    (async () => {
      const { token } = req.body || {};
      if (!token) return res.status(400).json({ ok: false, error: "token required" });
      const payload = await validateToken(token);
      res.json({ ok: true, payload });
    })().catch(() => {
      res.status(401).json({ ok: false, error: "invalid token" });
    });
  });

  app.post("/session/start", async (req, res) => {
    try {
      const { token, robloxUserId, robloxGameId, robloxPlaceId } = req.body || {};
      const payload = await validateToken(token);
      await prisma.session.update({
        where: { tokenJti: payload.jti },
        data: {
          robloxUserId: robloxUserId ? String(robloxUserId) : null,
          robloxGameId: robloxGameId ? String(robloxGameId) : null,
          robloxPlaceId: robloxPlaceId ? String(robloxPlaceId) : null,
          startedAt: new Date(),
          lastSeenAt: new Date(),
        },
      });
      res.json({ ok: true });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  app.post("/session/end", async (req, res) => {
    try {
      const { token } = req.body || {};
      const payload = await validateToken(token);
      await prisma.session.update({
        where: { tokenJti: payload.jti },
        data: { endedAt: new Date(), revoked: true },
      });
      res.json({ ok: true });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  return app;
}
