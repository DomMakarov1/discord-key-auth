import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { nanoid } from "nanoid";
import { config } from "./config.js";
import { prisma } from "./db.js";

export async function registerUser({ username, password, discordId }) {
  const exists = await prisma.user.findUnique({ where: { username } });
  if (exists) throw new Error("Username already exists");
  const passwordHash = await bcrypt.hash(password, 12);
  return prisma.user.create({
    data: { username, passwordHash, discordId },
  });
}

export async function loginUser({ username, password }) {
  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) throw new Error("Invalid credentials");
  if (user.blacklisted) throw new Error("User is blacklisted");
  const ok = await bcrypt.compare(password, user.passwordHash);
  if (!ok) throw new Error("Invalid credentials");

  const activeLicense = await prisma.license.findFirst({
    where: {
      userId: user.id,
      active: true,
      expiresAt: { gt: new Date() },
      tier: "Member",
    },
    orderBy: { expiresAt: "desc" },
  });
  if (!activeLicense) throw new Error("No active Member license");

  const jti = nanoid(24);
  const session = await prisma.session.create({
    data: {
      userId: user.id,
      tokenJti: jti,
      startedAt: new Date(),
      lastSeenAt: new Date(),
    },
  });

  const token = jwt.sign(
    { sub: user.id, username: user.username, tier: activeLicense.tier, jti },
    config.jwtSecret,
    { expiresIn: "1h" }
  );

  return { token, tier: activeLicense.tier, expiresAt: activeLicense.expiresAt, sessionId: session.id };
}

export function verifyToken(token) {
  return jwt.verify(token, config.jwtSecret);
}

export async function validateToken(token) {
  const payload = verifyToken(token);
  const userId = Number(payload.sub);
  if (!userId || !payload.jti) throw new Error("Invalid token payload");
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || user.blacklisted) throw new Error("User blocked");
  const session = await prisma.session.findUnique({ where: { tokenJti: payload.jti } });
  if (!session || session.revoked) throw new Error("Session revoked");
  await prisma.session.update({
    where: { id: session.id },
    data: { lastSeenAt: new Date() },
  });
  return payload;
}

export async function issueKey({ tier = "Member", durationDays = 30 }) {
  const code = `${tier.toUpperCase()}-${nanoid(20)}`;
  return prisma.key.create({
    data: { code, tier, durationDays },
  });
}

export async function redeemKey({ username, discordId, code }) {
  const user = username
    ? await prisma.user.findUnique({ where: { username } })
    : await prisma.user.findFirst({ where: { discordId } });
  if (!user) throw new Error("User not found");
  if (user.blacklisted) throw new Error("User is blacklisted");

  const key = await prisma.key.findUnique({ where: { code } });
  if (!key) throw new Error("Invalid key");
  if (key.redeemedAt) throw new Error("Key already redeemed");

  const now = new Date();
  const expiresAt = new Date(now.getTime() + key.durationDays * 24 * 60 * 60 * 1000);

  await prisma.$transaction([
    prisma.key.update({
      where: { id: key.id },
      data: { redeemedAt: now, redeemedById: user.id },
    }),
    prisma.license.create({
      data: {
        userId: user.id,
        tier: key.tier,
        active: true,
        expiresAt,
      },
    }),
  ]);

  return { tier: key.tier, expiresAt };
}

export async function getUserByUsername(username) {
  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) throw new Error("User not found");
  return user;
}

export async function statusUser(username) {
  const user = await getUserByUsername(username);
  const license = await prisma.license.findFirst({
    where: { userId: user.id, active: true },
    orderBy: { expiresAt: "desc" },
  });
  return { user, license };
}

export async function extendUser(username, days) {
  const user = await getUserByUsername(username);
  let license = await prisma.license.findFirst({
    where: { userId: user.id, active: true },
    orderBy: { expiresAt: "desc" },
  });
  const now = new Date();
  if (!license) {
    license = await prisma.license.create({
      data: {
        userId: user.id,
        tier: "Member",
        active: true,
        expiresAt: new Date(now.getTime() + days * 86400000),
      },
    });
    return license;
  }
  const base = license.expiresAt > now ? license.expiresAt : now;
  return prisma.license.update({
    where: { id: license.id },
    data: { expiresAt: new Date(base.getTime() + days * 86400000) },
  });
}

export async function revokeUser(username) {
  const user = await getUserByUsername(username);
  await prisma.license.updateMany({
    where: { userId: user.id, active: true },
    data: { active: false, expiresAt: new Date() },
  });
  await logoutAllSessions(user.username);
}

export async function resetPassword(username, newPassword) {
  const user = await getUserByUsername(username);
  const hash = await bcrypt.hash(newPassword, 12);
  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash: hash },
  });
  await logoutAllSessions(user.username);
}

export async function changePassword(discordId, oldPass, newPass) {
  const user = await prisma.user.findFirst({ where: { discordId } });
  if (!user) throw new Error("No account linked to this Discord");
  const ok = await bcrypt.compare(oldPass, user.passwordHash);
  if (!ok) throw new Error("Old password incorrect");
  const hash = await bcrypt.hash(newPass, 12);
  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash: hash },
  });
}

export async function unlinkDiscord(discordId) {
  const user = await prisma.user.findFirst({ where: { discordId } });
  if (!user) throw new Error("No linked account");
  await prisma.user.update({
    where: { id: user.id },
    data: { discordId: null },
  });
}

export async function transferDiscord(username, targetDiscordId) {
  const user = await getUserByUsername(username);
  const existing = await prisma.user.findFirst({ where: { discordId: targetDiscordId } });
  if (existing && existing.id !== user.id) throw new Error("Target Discord already linked");
  await prisma.user.update({
    where: { id: user.id },
    data: { discordId: targetDiscordId },
  });
}

export async function assignKey(username, code) {
  const user = await getUserByUsername(username);
  const key = await prisma.key.findUnique({ where: { code } });
  if (!key) throw new Error("Key not found");
  if (key.redeemedAt) throw new Error("Key already redeemed");
  return prisma.key.update({
    where: { id: key.id },
    data: { assignedToId: user.id },
  });
}

export async function listKeys({ username, discordId, filter }) {
  let where = {};
  if (username || discordId) {
    const user = username
      ? await getUserByUsername(username)
      : await prisma.user.findFirst({ where: { discordId } });
    if (!user) throw new Error("User not found");
    where = {
      OR: [{ assignedToId: user.id }, { redeemedById: user.id }],
    };
  }
  if (filter === "used") where.redeemedAt = { not: null };
  if (filter === "unused") where.redeemedAt = null;
  return prisma.key.findMany({
    where,
    orderBy: { createdAt: "desc" },
    take: 50,
  });
}

export async function setBlacklist(username, blacklisted) {
  const user = await getUserByUsername(username);
  await prisma.user.update({
    where: { id: user.id },
    data: { blacklisted },
  });
  if (blacklisted) await logoutAllSessions(username);
}

export async function getSessions(username, scope = "all") {
  const user = await getUserByUsername(username);
  const where = { userId: user.id };
  if (scope === "current") where.endedAt = null;
  if (scope === "previous") where.endedAt = { not: null };
  return prisma.session.findMany({
    where,
    orderBy: { startedAt: "desc" },
    take: 30,
  });
}

export async function logoutAllSessions(username) {
  const user = await getUserByUsername(username);
  await prisma.session.updateMany({
    where: { userId: user.id, endedAt: null },
    data: { revoked: true, endedAt: new Date() },
  });
}

export async function issueBulk(days, count) {
  const toCreate = [];
  for (let i = 0; i < count; i += 1) {
    toCreate.push({
      code: `MEMBER-${nanoid(20)}`,
      tier: "Member",
      durationDays: days,
    });
  }
  await prisma.key.createMany({ data: toCreate });
  return toCreate;
}

export async function setTier(username, rank) {
  const user = await getUserByUsername(username);
  return prisma.user.update({
    where: { id: user.id },
    data: { rank },
  });
}

export async function deleteAccount(username) {
  const user = await getUserByUsername(username);
  await prisma.$transaction([
    prisma.session.deleteMany({ where: { userId: user.id } }),
    prisma.license.deleteMany({ where: { userId: user.id } }),
    prisma.key.updateMany({
      where: { assignedToId: user.id },
      data: { assignedToId: null },
    }),
    prisma.key.updateMany({
      where: { redeemedById: user.id },
      data: { redeemedById: null },
    }),
    prisma.user.delete({ where: { id: user.id } }),
  ]);
  pendingClientCommands.delete(user.id);
  return { username: user.username };
}

export async function scriptLoginWithPassword({ username, password }) {
  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) throw new Error("Account does not exist");
  if (user.blacklisted) throw new Error("Account blacklisted");
  const ok = await bcrypt.compare(password, user.passwordHash);
  if (!ok) throw new Error("Invalid username or password");

  const now = new Date();
  const activeLicense = await prisma.license.findFirst({
    where: {
      userId: user.id,
      active: true,
      expiresAt: { gt: now },
      tier: "Member",
    },
    orderBy: { expiresAt: "desc" },
  });
  if (!activeLicense) throw new Error("No active key/license");

  const key = await prisma.key.findFirst({
    where: {
      tier: activeLicense.tier,
      OR: [{ assignedToId: user.id }, { redeemedById: user.id }],
    },
    orderBy: [{ redeemedAt: "desc" }, { createdAt: "desc" }],
  });
  if (!key) throw new Error("No affiliated key found");

  const jti = nanoid(24);
  await prisma.session.create({
    data: {
      userId: user.id,
      tokenJti: jti,
      startedAt: now,
      lastSeenAt: now,
    },
  });

  const token = jwt.sign(
    { sub: user.id, username: user.username, tier: activeLicense.tier, jti },
    config.jwtSecret,
    { expiresIn: "1h" }
  );

  return {
    token,
    tier: activeLicense.tier,
    expiresAt: activeLicense.expiresAt,
    key: key.code,
  };
}

export async function scriptLoginWithSavedKey({ username, keyCode }) {
  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) throw new Error("Account does not exist");
  if (user.blacklisted) throw new Error("Account blacklisted");

  const key = await prisma.key.findUnique({ where: { code: keyCode } });
  if (!key) throw new Error("Invalid key");
  const affiliated =
    (key.assignedToId && key.assignedToId === user.id) ||
    (key.redeemedById && key.redeemedById === user.id);
  if (!affiliated) throw new Error("Key not affiliated");

  const now = new Date();
  const activeLicense = await prisma.license.findFirst({
    where: {
      userId: user.id,
      active: true,
      tier: "Member",
      expiresAt: { gt: now },
    },
    orderBy: { expiresAt: "desc" },
  });
  if (!activeLicense) throw new Error("No active key/license");

  const jti = nanoid(24);
  await prisma.session.create({
    data: { userId: user.id, tokenJti: jti, startedAt: now, lastSeenAt: now },
  });

  const token = jwt.sign(
    { sub: user.id, username: user.username, tier: activeLicense.tier, jti },
    config.jwtSecret,
    { expiresIn: "1h" }
  );
  return { token, tier: activeLicense.tier, expiresAt: activeLicense.expiresAt, key: key.code };
}

// --- Remote admin: presence + pending commands for Discord /kick and /message ---

const pendingClientCommands = new Map();
let clientCommandSeq = 1;

function pushCommand(userId, cmd) {
  const list = pendingClientCommands.get(userId) || [];
  list.push({ id: clientCommandSeq++, ...cmd });
  pendingClientCommands.set(userId, list);
}

export async function updateScriptPresence(token, { robloxUserId, placeId, gameId }) {
  const payload = await validateToken(token);
  const userId = Number(payload.sub);
  const session = await prisma.session.findUnique({ where: { tokenJti: payload.jti } });
  if (!session || session.endedAt || session.revoked) throw new Error("Session invalid");

  await prisma.session.update({
    where: { id: session.id },
    data: {
      robloxUserId: robloxUserId != null ? String(robloxUserId) : session.robloxUserId,
      robloxPlaceId: placeId != null ? String(placeId) : session.robloxPlaceId,
      robloxGameId: gameId != null ? String(gameId) : session.robloxGameId,
      lastSeenAt: new Date(),
    },
  });
  return { userId };
}

export function getAndClearPendingCommands(userId) {
  const list = pendingClientCommands.get(userId);
  pendingClientCommands.delete(userId);
  return list || [];
}

// Keep this generous so temporary network hiccups or brief executor stalls
// don't cause false "not live" failures for /kick and /message.
const PRESENCE_MAX_AGE_MS = 15 * 60_000;

async function assertUserInGameWithScript(userId) {
  const cutoff = new Date(Date.now() - PRESENCE_MAX_AGE_MS);
  const session = await prisma.session.findFirst({
    where: {
      userId,
      endedAt: null,
      revoked: false,
      lastSeenAt: { gte: cutoff },
      robloxUserId: { not: null },
    },
    orderBy: { lastSeenAt: "desc" },
  });
  if (!session) {
    throw new Error(
      "No recent UniversalAdmin heartbeat for that user (ask them to re-run latest script and wait ~20s)"
    );
  }
}

export async function enqueueKickByDiscordId(discordId) {
  const user = await prisma.user.findFirst({ where: { discordId: String(discordId) } });
  if (!user) throw new Error("No script account linked to that Discord user");
  await assertUserInGameWithScript(user.id);
  pushCommand(user.id, { action: "kick" });
  return { username: user.username };
}

export async function enqueueMessageByDiscordId(discordId, message) {
  const text = (message || "").trim();
  if (!text) throw new Error("Message required");
  if (text.length > 500) throw new Error("Message too long (max 500)");

  const user = await prisma.user.findFirst({ where: { discordId: String(discordId) } });
  if (!user) throw new Error("No script account linked to that Discord user");
  await assertUserInGameWithScript(user.id);
  pushCommand(user.id, { action: "message", message: text });
  return { username: user.username };
}
