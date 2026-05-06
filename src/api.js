import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import express from "express";
import {
  loginUser,
  scriptLoginWithPassword,
  scriptLoginWithSavedKey,
  validateToken,
  updateScriptPresence,
  fetchPendingClientCommands,
  ackClientCommand,
  enqueuePeerClientAction,
  getScriptAccessStatus,
  listOnlinePeers,
  getFriends,
  sendFriendRequest,
  acceptFriendRequest,
  denyFriendRequest,
  removeFriend,
  requestJoinFriend,
  respondToJoinRequest,
  sendFriendMessage,
  getFriendMessages,
} from "./auth.js";
import { prisma } from "./db.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function createApi() {
  const app = express();
  app.set("trust proxy", true);
  const getRequestIp = (req) => {
    const forwarded = req.headers["x-forwarded-for"];
    if (typeof forwarded === "string" && forwarded.trim() !== "") {
      return forwarded.split(",")[0].trim();
    }
    return req.ip || req.socket?.remoteAddress || null;
  };

  const sendAuthFailure = (res, err, fallbackStatus = 401) => {
    if (err && err.authCode) {
      return res.status(fallbackStatus).json({
        ok: false,
        error: err.message,
        code: err.authCode,
        lockoutUntil: err.lockoutUntil || undefined,
      });
    }
    return res.status(fallbackStatus).json({ ok: false, error: err?.message || "error" });
  };
  const extractToken = (req) => {
    const auth = req.headers.authorization || "";
    const m = auth.match(/^Bearer\s+(.+)$/i);
    if (m && m[1]) return m[1];
    if (req.body && typeof req.body.token === "string" && req.body.token.trim() !== "") {
      return req.body.token.trim();
    }
    return null;
  };

  // Raw UniversalAdmin client script for HttpGet + loadstring (rejoin auto-reexec).
  // Tries public/ first, then repo-root UniversalAdmin.lua when the full monorepo is deployed.
  app.get("/UniversalAdmin.lua", (_req, res) => {
    const candidates = [
      path.join(__dirname, "../../UniversalAdmin.lua"),
      path.join(__dirname, "../public/UniversalAdmin.lua"),
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
      const { username, password, hwid } = req.body || {};
      if (!username || !password) {
        return res.status(400).json({ ok: false, error: "username and password required" });
      }
      const result = await scriptLoginWithPassword({
        username,
        password,
        hwid,
        ip: getRequestIp(req),
      });
      res.json({ ok: true, ...result });
    } catch (err) {
      return sendAuthFailure(res, err);
    }
  });

  app.post("/auth/script-login-key", async (req, res) => {
    try {
      const { username, key, hwid } = req.body || {};
      if (!username) {
        return res.status(400).json({ ok: false, error: "username required" });
      }
      const result = await scriptLoginWithSavedKey({
        username,
        keyCode: key,
        hwid,
        ip: getRequestIp(req),
      });
      res.json({ ok: true, ...result });
    } catch (err) {
      return sendAuthFailure(res, err);
    }
  });

  app.post("/auth/access-status", async (req, res) => {
    try {
      const { hwid } = req.body || {};
      const status = await getScriptAccessStatus({
        hwid,
        ip: getRequestIp(req),
      });
      res.json({ ok: true, ...status });
    } catch (err) {
      return sendAuthFailure(res, err);
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

  app.post("/client/presence", async (req, res) => {
    try {
      const token = extractToken(req);
      if (!token) return res.status(401).json({ ok: false, error: "token required" });
      const { robloxUserId, robloxUsername, placeId, gameId, hwid, accentPrimary } = req.body || {};
      await updateScriptPresence(token, {
        robloxUserId,
        robloxUsername,
        placeId,
        gameId,
        hwid,
        accentPrimary,
        ipAddress: getRequestIp(req),
      });
      const roster = await listOnlinePeers(token, {});
      res.json({ ok: true, peers: roster.peers || [] });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  app.get("/client/commands", async (req, res) => {
    try {
      const token = extractToken(req);
      if (!token) return res.status(401).json({ ok: false, error: "token required" });
      const commands = await fetchPendingClientCommands(token);
      res.json({ ok: true, commands });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  // POST variant is more executor-friendly for client polling than GET with custom headers.
  app.post("/client/commands", async (req, res) => {
    try {
      const token = extractToken(req);
      if (!token) return res.status(401).json({ ok: false, error: "token required" });
      const commands = await fetchPendingClientCommands(token);
      res.json({ ok: true, commands });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  app.post("/client/ack", async (req, res) => {
    try {
      const token = extractToken(req);
      if (!token) return res.status(401).json({ ok: false, error: "token required" });
      const { commandId, status, error } = req.body || {};
      await ackClientCommand(token, commandId, status, error);
      res.json({ ok: true });
    } catch (err) {
      res.status(401).json({ ok: false, error: err.message });
    }
  });

  app.post("/client/peer-action", async (req, res) => {
    try {
      const token = extractToken(req);
      if (!token) return res.status(401).json({ ok: false, error: "token required" });
      const { target, action, payload } = req.body || {};
      if (!target || !action) {
        return res.status(400).json({ ok: false, error: "target and action required" });
      }
      const out = await enqueuePeerClientAction(token, {
        targetIdentity: target,
        action,
        payload: (payload && typeof payload === "object") ? payload : {},
      });
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
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

  // ── Friends ──────────────────────────────────────────

  const friendsAuth = (req) => {
    const tok = extractToken(req);
    if (!tok) return null;
    return validateToken(tok).catch(() => null);
  };

  const requireFriendsAuth = async (req, res) => {
    const tok = extractToken(req);
    if (!tok) { res.status(401).json({ ok: false, error: "token required" }); return null; }
    try {
      return await validateToken(tok);
    } catch {
      res.status(401).json({ ok: false, error: "invalid token" });
      return null;
    }
  };

  app.get("/friends", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const userId = Number(payload.sub);
      const data = await getFriends(userId);
      res.json({ ok: true, ...data });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  app.post("/friends/request", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const { username } = req.body || {};
      if (!username) return res.status(400).json({ ok: false, error: "username required" });
      const out = await sendFriendRequest(Number(payload.sub), username);
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  // Keep /friends/add as alias for backwards compat
  app.post("/friends/add", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const { username } = req.body || {};
      if (!username) return res.status(400).json({ ok: false, error: "username required" });
      const out = await sendFriendRequest(Number(payload.sub), username);
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  app.post("/friends/accept", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const { requestId } = req.body || {};
      if (requestId == null) return res.status(400).json({ ok: false, error: "requestId required" });
      const out = await acceptFriendRequest(Number(payload.sub), requestId);
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  app.post("/friends/deny", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const { requestId } = req.body || {};
      if (requestId == null) return res.status(400).json({ ok: false, error: "requestId required" });
      const out = await denyFriendRequest(Number(payload.sub), requestId);
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  app.post("/friends/remove", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const { username } = req.body || {};
      if (!username) return res.status(400).json({ ok: false, error: "username required" });
      const out = await removeFriend(Number(payload.sub), username);
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  app.post("/friends/join", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const { username } = req.body || {};
      if (!username) return res.status(400).json({ ok: false, error: "username required" });
      const out = await requestJoinFriend(Number(payload.sub), username);
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  app.post("/friends/join-respond", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const { username, accepted } = req.body || {};
      if (!username) return res.status(400).json({ ok: false, error: "username required" });
      const out = await respondToJoinRequest(Number(payload.sub), username, accepted === true);
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  app.post("/friends/message", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const { username, content, text } = req.body || {};
      const msgContent = content || text;
      if (!username || !msgContent) return res.status(400).json({ ok: false, error: "username and content required" });
      const out = await sendFriendMessage(Number(payload.sub), username, msgContent);
      res.json({ ok: true, ...out });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
    }
  });

  app.get("/friends/messages", async (req, res) => {
    try {
      const payload = await requireFriendsAuth(req, res);
      if (!payload) return;
      const friendUsername = req.query.with || null;
      const data = await getFriendMessages(Number(payload.sub), friendUsername);
      res.json({ ok: true, ...data });
    } catch (err) {
      res.status(400).json({ ok: false, error: err.message });
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
