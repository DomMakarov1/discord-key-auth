import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { nanoid } from "nanoid";
import { config } from "./config.js";
import { prisma } from "./db.js";
import { logScriptExecution, logScriptLogin } from "./discordLogs.js";

const TIER_ORDER = ["Owner", "Premium", "Member"];
const TIER_WEIGHT = { Member: 1, Premium: 2, Owner: 3 };
const liveAccentByUserId = new Map();

function normalizeTier(input, { allowNull = false } = {}) {
  if (input == null) {
    if (allowNull) return null;
    return "Member";
  }
  const raw = String(input).trim().toLowerCase();
  if (raw === "" && allowNull) return null;
  if (raw === "owner") return "Owner";
  if (raw === "premium") return "Premium";
  if (raw === "member") return "Member";
  throw new Error("Invalid tier. Use Member, Premium, or Owner");
}

async function getBestActiveLicense(userId) {
  const now = new Date();
  const licenses = await prisma.license.findMany({
    where: {
      userId,
      active: true,
      expiresAt: { gt: now },
      tier: { in: TIER_ORDER },
    },
    orderBy: { expiresAt: "desc" },
  });
  if (!licenses.length) return null;
  licenses.sort((a, b) => TIER_ORDER.indexOf(a.tier) - TIER_ORDER.indexOf(b.tier));
  return licenses[0];
}

function hasTierAtLeast(tier, minimum) {
  return (TIER_WEIGHT[String(tier)] || 0) >= (TIER_WEIGHT[String(minimum)] || 0);
}

function maxTier(a, b) {
  return hasTierAtLeast(a, b) ? a : b;
}

function parseBlacklistDuration(input) {
  const raw = String(input || "").trim().toLowerCase();
  if (!raw) throw new Error("Blacklist duration required (infinite, 5h, 10d)");
  if (raw === "infinite" || raw === "inf" || raw === "perm" || raw === "permanent") {
    return null;
  }
  const m = raw.match(/^(\d+)\s*([hd])$/i);
  if (!m) {
    throw new Error("Invalid duration. Use infinite or formats like 5h / 10d");
  }
  const amount = Number(m[1]);
  const unit = m[2].toLowerCase();
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error("Duration must be a positive number");
  }
  const ms = unit === "h" ? amount * 60 * 60 * 1000 : amount * 24 * 60 * 60 * 1000;
  return new Date(Date.now() + ms);
}

async function isUserBlacklistedNow(user) {
  if (!user || !user.blacklisted) return false;
  if (!user.blacklistedUntil) return true; // infinite
  if (new Date(user.blacklistedUntil).getTime() > Date.now()) return true;
  await prisma.user.update({
    where: { id: user.id },
    data: { blacklisted: false, blacklistedUntil: null },
  });
  return false;
}

/** Structured auth errors for HTTP layer (code + optional lockout time). */
function authReject(message, code, extra = {}) {
  const e = new Error(message);
  e.authCode = code;
  if (extra.lockoutUntil != null) e.lockoutUntil = extra.lockoutUntil;
  return e;
}

function utcDayKey(d = new Date()) {
  return d.toISOString().slice(0, 10);
}

export function normalizeClientHwid(hwid) {
  if (hwid == null) return null;
  const s = String(hwid).trim();
  if (!s) return null;
  return s.slice(0, 200);
}

export function normalizeClientIp(ip) {
  if (ip == null) return null;
  const s = String(ip).trim();
  if (!s) return null;
  return s.slice(0, 100);
}

async function findAccessBan({ hwid, ip }) {
  const or = [];
  if (hwid) or.push({ hwid });
  if (ip) or.push({ ip });
  if (!or.length) return null;
  return prisma.accessBan.findFirst({
    where: { OR: or },
    orderBy: { createdAt: "desc" },
  });
}

export async function assertNotAccessBanned({ hwid, ip }) {
  const ban = await findAccessBan({ hwid, ip });
  if (!ban) return;
  const reason = ban.reason ? ` Reason: ${ban.reason}` : "";
  throw authReject(
    `Your device cannot sign in. Appeal in the Universal Admin Discord.${reason}`,
    "ACCESS_BANNED"
  );
}

async function assertHwidNotLocked(hwid) {
  if (!hwid) return;
  let row = await prisma.hwidLoginState.findUnique({ where: { hwid } });
  if (!row) return;
  if (row.lockedUntil && new Date(row.lockedUntil) <= new Date()) {
    await prisma.hwidLoginState.update({
      where: { hwid },
      data: { lockedUntil: null },
    });
    return;
  }
  if (row.lockedUntil && new Date(row.lockedUntil) > new Date()) {
    const iso = new Date(row.lockedUntil).toISOString();
    throw authReject(
      `Too many failed login attempts from this device. Try again after ${iso}.`,
      "LOGIN_LOCKOUT",
      { lockoutUntil: iso }
    );
  }
}

async function recordHwidLoginFailure(hwid) {
  if (!hwid) return;
  const today = utcDayKey();
  let row = await prisma.hwidLoginState.findUnique({ where: { hwid } });
  if (!row) {
    row = await prisma.hwidLoginState.create({
      data: { hwid, failCount: 0, escalation: 0, dayKey: today, lockedUntil: null },
    });
  }
  if (row.lockedUntil && new Date(row.lockedUntil) > new Date()) {
    return;
  }
  let { failCount, escalation, dayKey } = row;
  if (dayKey !== today) {
    failCount = 0;
    escalation = 0;
    dayKey = today;
  }
  failCount += 1;
  if (failCount < 5) {
    await prisma.hwidLoginState.update({
      where: { hwid },
      data: { failCount, escalation, dayKey },
    });
    return;
  }
  const durations = [5 * 60 * 1000, 20 * 60 * 1000, 60 * 60 * 1000];
  const idx = Math.min(escalation, 2);
  const lockedUntil = new Date(Date.now() + durations[idx]);
  const nextEsc = Math.min(escalation + 1, 2);
  await prisma.hwidLoginState.update({
    where: { hwid },
    data: {
      failCount: 0,
      escalation: nextEsc,
      dayKey: today,
      lockedUntil,
    },
  });
}

async function clearHwidLoginOnSuccess(hwid) {
  if (!hwid) return;
  await prisma.hwidLoginState.upsert({
    where: { hwid },
    create: { hwid, failCount: 0, escalation: 0, dayKey: utcDayKey(), lockedUntil: null },
    update: { failCount: 0, lockedUntil: null },
  });
}

export async function getScriptAccessStatus({ hwid, ip }) {
  const h = normalizeClientHwid(hwid);
  const p = normalizeClientIp(ip);
  try {
    await assertNotAccessBanned({ hwid: h, ip: p });
  } catch (e) {
    if (e.authCode === "ACCESS_BANNED") {
      return { canLogin: false, code: e.authCode, message: e.message, lockoutUntil: null };
    }
    throw e;
  }
  try {
    await assertHwidNotLocked(h);
  } catch (e) {
    if (e.authCode === "LOGIN_LOCKOUT") {
      return {
        canLogin: false,
        code: e.authCode,
        message: e.message,
        lockoutUntil: e.lockoutUntil || null,
      };
    }
    throw e;
  }
  return { canLogin: true, code: null, message: null, lockoutUntil: null };
}

export async function addAccessBan({ hwid, ip, reason, createdByDiscordId }) {
  const h = normalizeClientHwid(hwid);
  const p = normalizeClientIp(ip);
  if (!h && !p) throw new Error("hwid and/or ip required");
  return prisma.accessBan.create({
    data: {
      hwid: h || null,
      ip: p || null,
      reason: reason ? String(reason).slice(0, 500) : null,
      createdByDiscordId: createdByDiscordId ? String(createdByDiscordId) : null,
    },
  });
}

export async function removeAccessBans({ hwid, ip }) {
  const h = normalizeClientHwid(hwid);
  const p = normalizeClientIp(ip);
  const or = [];
  if (h) or.push({ hwid: h });
  if (p) or.push({ ip: p });
  if (!or.length) throw new Error("hwid and/or ip required to unban");
  const out = await prisma.accessBan.deleteMany({ where: { OR: or } });
  return { deleted: out.count };
}

export async function removeAccessBansForUserIdentity(identity) {
  const user = await getUserByIdentity(identity);
  const sess = await prisma.session.findFirst({
    where: { userId: user.id },
    orderBy: { lastSeenAt: "desc" },
  });
  const h = normalizeClientHwid(sess?.hwid);
  const p = normalizeClientIp(sess?.lastIp);
  if (!h && !p) throw new Error("No HWID/IP on record for this user");
  return removeAccessBans({ hwid: h, ip: p });
}

export async function banFromUserLatestSession(identity, { reason, createdByDiscordId, mode }) {
  const user = await getUserByIdentity(identity);
  const sess = await prisma.session.findFirst({
    where: { userId: user.id },
    orderBy: { lastSeenAt: "desc" },
  });
  const hwid = normalizeClientHwid(sess?.hwid);
  const ip = normalizeClientIp(sess?.lastIp);
  if (mode === "hwid") {
    if (!hwid) throw new Error("No HWID on file for this user (need a recent script run / presence)");
    return addAccessBan({ hwid, reason, createdByDiscordId });
  }
  if (mode === "ip") {
    if (!ip) throw new Error("No IP on file for this user (need a recent script run / presence)");
    return addAccessBan({ ip, reason, createdByDiscordId });
  }
  if (mode === "full") {
    if (!hwid && !ip) throw new Error("No HWID/IP on file for this user (need a recent script run / presence)");
    return addAccessBan({ hwid: hwid || undefined, ip: ip || undefined, reason, createdByDiscordId });
  }
  throw new Error("Invalid ban mode");
}

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
  if (await isUserBlacklistedNow(user)) throw new Error("User is blacklisted");
  const ok = await bcrypt.compare(password, user.passwordHash);
  if (!ok) throw new Error("Invalid credentials");

  const activeLicense = await getBestActiveLicense(user.id);
  if (!activeLicense) throw new Error("No active license");

  const jti = nanoid(24);
  const session = await prisma.session.create({
    data: {
      userId: user.id,
      tokenJti: jti,
      startedAt: new Date(),
      lastSeenAt: new Date(),
    },
  });

  const effectiveTier = maxTier(activeLicense.tier, user.rank || "Member");
  const token = jwt.sign(
    { sub: user.id, username: user.username, tier: effectiveTier, jti },
    config.jwtSecret,
    { expiresIn: "1h" }
  );

  return { token, tier: effectiveTier, expiresAt: activeLicense.expiresAt, sessionId: session.id };
}

export function verifyToken(token) {
  return jwt.verify(token, config.jwtSecret);
}

export async function validateToken(token) {
  const payload = verifyToken(token);
  const userId = Number(payload.sub);
  if (!userId || !payload.jti) throw new Error("Invalid token payload");
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw new Error("User blocked");
  if (await isUserBlacklistedNow(user)) throw new Error("User blocked");
  const session = await prisma.session.findUnique({ where: { tokenJti: payload.jti } });
  if (!session || session.revoked) throw new Error("Session revoked");
  await prisma.session.update({
    where: { id: session.id },
    data: { lastSeenAt: new Date() },
  });
  return payload;
}

export async function issueKey({ tier = "Member", durationDays = 30 }) {
  const normTier = normalizeTier(tier);
  const code = `${normTier.toUpperCase()}-${nanoid(20)}`;
  return prisma.key.create({
    data: { code, tier: normTier, durationDays },
  });
}

export async function redeemKey({ username, discordId, code }) {
  const user = username
    ? await prisma.user.findUnique({ where: { username } })
    : await prisma.user.findFirst({ where: { discordId } });
  if (!user) throw new Error("User not found");
  if (await isUserBlacklistedNow(user)) throw new Error("User is blacklisted");

  const key = await prisma.key.findUnique({ where: { code } });
  if (!key) throw new Error("Invalid key");
  if (key.redeemedAt) throw new Error("Key already redeemed");
  if (key.tier === "Owner" && !config.adminDiscordIds.includes(String(user.discordId || ""))) {
    throw new Error("Owner keys can only be redeemed by owner accounts");
  }

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

function normalizeIdentity(identity) {
  return String(identity || "").trim();
}

function parseDiscordIdFromIdentity(identity) {
  const raw = normalizeIdentity(identity);
  if (!raw) return null;
  const mention = raw.match(/^<@!?(\d+)>$/);
  if (mention) return mention[1];
  if (/^\d{17,20}$/.test(raw)) return raw;
  return null;
}

export async function getUserByUsername(username) {
  const user = await prisma.user.findUnique({ where: { username: normalizeIdentity(username) } });
  if (!user) throw new Error("User not found");
  return user;
}

export async function getUserByIdentity(identity) {
  const raw = normalizeIdentity(identity);
  if (!raw) throw new Error("User identity required");

  const discordId = parseDiscordIdFromIdentity(raw);
  if (discordId) {
    const byDiscord = await prisma.user.findFirst({ where: { discordId } });
    if (byDiscord) return byDiscord;
  }

  const byUsername = await prisma.user.findUnique({ where: { username: raw } });
  if (byUsername) return byUsername;

  throw new Error("User not found (use linked Discord @mention/id or exact username)");
}

export async function statusUser(identity) {
  const user = await getUserByIdentity(identity);
  const license = await prisma.license.findFirst({
    where: { userId: user.id, active: true },
    orderBy: { expiresAt: "desc" },
  });
  return { user, license };
}

export async function extendUser(identity, days) {
  const user = await getUserByIdentity(identity);
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

export async function revokeUser(identity) {
  const user = await getUserByIdentity(identity);
  await prisma.license.updateMany({
    where: { userId: user.id, active: true },
    data: { active: false, expiresAt: new Date() },
  });
  await logoutAllSessions(user.username);
}

export async function resetPassword(identity, newPassword) {
  const user = await getUserByIdentity(identity);
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
  const user = await getUserByIdentity(username);
  const existing = await prisma.user.findFirst({ where: { discordId: targetDiscordId } });
  if (existing && existing.id !== user.id) throw new Error("Target Discord already linked");
  await prisma.user.update({
    where: { id: user.id },
    data: { discordId: targetDiscordId },
  });
}

export async function assignKey(username, code) {
  const user = await getUserByIdentity(username);
  const key = await prisma.key.findUnique({ where: { code } });
  if (!key) throw new Error("Key not found");
  if (key.redeemedAt) throw new Error("Key already redeemed");
  if (key.tier === "Owner" && !config.adminDiscordIds.includes(String(user.discordId || ""))) {
    throw new Error("Owner keys can only be assigned to owner Discord accounts");
  }
  return prisma.key.update({
    where: { id: key.id },
    data: { assignedToId: user.id },
  });
}

export async function listKeys({ username, discordId, filter }) {
  let where = {};
  if (username || discordId) {
    const user = username
      ? await getUserByIdentity(username)
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

export async function setBlacklist(identity, blacklisted, durationInput = null) {
  const user = await getUserByIdentity(identity);
  const data = blacklisted
    ? { blacklisted: true, blacklistedUntil: parseBlacklistDuration(durationInput) }
    : { blacklisted: false, blacklistedUntil: null };
  await prisma.user.update({
    where: { id: user.id },
    data,
  });
  if (blacklisted) await logoutAllSessions(user.username);
  return { username: user.username, blacklistedUntil: data.blacklistedUntil };
}

export async function getSessions(identity, scope = "all") {
  const user = await getUserByIdentity(identity);
  const where = { userId: user.id };
  if (scope === "current") where.endedAt = null;
  if (scope === "previous") where.endedAt = { not: null };
  return prisma.session.findMany({
    where,
    orderBy: { startedAt: "desc" },
    take: 30,
  });
}

export async function logoutAllSessions(identity) {
  const user = await getUserByIdentity(identity);
  await prisma.session.updateMany({
    where: { userId: user.id, endedAt: null },
    data: { revoked: true, endedAt: new Date() },
  });
}

export async function issueBulk(days, count, tierInput = "Member") {
  const tier = normalizeTier(tierInput);
  const toCreate = [];
  for (let i = 0; i < count; i += 1) {
    toCreate.push({
      code: `${tier.toUpperCase()}-${nanoid(20)}`,
      tier,
      durationDays: days,
    });
  }
  await prisma.key.createMany({ data: toCreate });
  return toCreate;
}

export async function setTier(username, rank) {
  const user = await getUserByIdentity(username);
  const normRank = normalizeTier(rank);
  if (normRank === "Owner" && !config.adminDiscordIds.includes(String(user.discordId || ""))) {
    throw new Error("Owner rank can only be set for configured owner Discord accounts");
  }
  return prisma.user.update({
    where: { id: user.id },
    data: { rank: normRank },
  });
}

export async function deleteAccount(username) {
  const user = await getUserByIdentity(username);
  await prisma.$transaction([
    prisma.warning.deleteMany({ where: { userId: user.id } }),
    prisma.clientCommand.deleteMany({ where: { userId: user.id } }),
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
  return { username: user.username };
}

export async function scriptLoginWithPassword({ username, password, hwid, ip }) {
  const h = normalizeClientHwid(hwid);
  const p = normalizeClientIp(ip);
  await assertNotAccessBanned({ hwid: h, ip: p });
  await assertHwidNotLocked(h);

  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) {
    await recordHwidLoginFailure(h);
    throw new Error("Invalid username or password");
  }
  if (await isUserBlacklistedNow(user)) throw new Error("Account blacklisted");
  const ok = await bcrypt.compare(password, user.passwordHash);
  if (!ok) {
    await recordHwidLoginFailure(h);
    throw new Error("Invalid username or password");
  }

  const now = new Date();
  const activeLicense = await getBestActiveLicense(user.id);
  if (!activeLicense) {
    await recordHwidLoginFailure(h);
    throw new Error("No active key/license");
  }

  const key = await prisma.key.findFirst({
    where: {
      tier: activeLicense.tier,
      OR: [{ assignedToId: user.id }, { redeemedById: user.id }],
    },
    orderBy: [{ redeemedAt: "desc" }, { createdAt: "desc" }],
  });
  if (!key) {
    await recordHwidLoginFailure(h);
    throw new Error("No affiliated key found");
  }

  const jti = nanoid(24);
  await prisma.session.create({
    data: {
      userId: user.id,
      tokenJti: jti,
      startedAt: now,
      lastSeenAt: now,
    },
  });

  const effectiveTier = maxTier(activeLicense.tier, user.rank || "Member");
  const token = jwt.sign(
    { sub: user.id, username: user.username, tier: effectiveTier, jti },
    config.jwtSecret,
    { expiresIn: "1h" }
  );
  await logScriptLogin(config, { username: user.username, tier: effectiveTier, jti }, {
    method: "password",
    discordId: user.discordId || null,
    keyCode: key.code,
  });

  await clearHwidLoginOnSuccess(h);

  return {
    token,
    tier: effectiveTier,
    expiresAt: activeLicense.expiresAt,
    key: key.code,
  };
}

export async function scriptLoginWithSavedKey({ username, keyCode, hwid, ip }) {
  const h = normalizeClientHwid(hwid);
  const p = normalizeClientIp(ip);
  await assertNotAccessBanned({ hwid: h, ip: p });
  await assertHwidNotLocked(h);

  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) {
    await recordHwidLoginFailure(h);
    throw new Error("Account does not exist");
  }
  if (await isUserBlacklistedNow(user)) throw new Error("Account blacklisted");

  const key = await prisma.key.findUnique({ where: { code: keyCode } });
  if (!key) {
    await recordHwidLoginFailure(h);
    throw new Error("Invalid key");
  }
  const affiliated =
    (key.assignedToId && key.assignedToId === user.id) ||
    (key.redeemedById && key.redeemedById === user.id);
  if (!affiliated) {
    await recordHwidLoginFailure(h);
    throw new Error("Key not affiliated");
  }

  const now = new Date();
  const activeLicense = await getBestActiveLicense(user.id);
  if (!activeLicense) {
    await recordHwidLoginFailure(h);
    throw new Error("No active key/license");
  }

  const jti = nanoid(24);
  await prisma.session.create({
    data: { userId: user.id, tokenJti: jti, startedAt: now, lastSeenAt: now },
  });

  const effectiveTier = maxTier(activeLicense.tier, user.rank || "Member");
  const token = jwt.sign(
    { sub: user.id, username: user.username, tier: effectiveTier, jti },
    config.jwtSecret,
    { expiresIn: "1h" }
  );
  await logScriptLogin(config, { username: user.username, tier: effectiveTier, jti }, {
    method: "saved_key",
    discordId: user.discordId || null,
    keyCode,
  });
  await clearHwidLoginOnSuccess(h);
  return { token, tier: effectiveTier, expiresAt: activeLicense.expiresAt, key: key.code };
}

// --- Remote admin: persisted command queue + heartbeat diagnostics ---

export async function updateScriptPresence(token, { robloxUserId, robloxUsername, placeId, gameId, hwid, ipAddress, accentPrimary }) {
  const payload = await validateToken(token);
  const userId = Number(payload.sub);
  const session = await prisma.session.findUnique({ where: { tokenJti: payload.jti } });
  if (!session || session.endedAt || session.revoked) throw new Error("Session invalid");

  const updated = await prisma.session.update({
    where: { id: session.id },
    data: {
      robloxUserId: robloxUserId != null ? String(robloxUserId) : session.robloxUserId,
      robloxUsername: robloxUsername != null ? String(robloxUsername) : session.robloxUsername,
      robloxPlaceId: placeId != null ? String(placeId) : session.robloxPlaceId,
      robloxGameId: gameId != null ? String(gameId) : session.robloxGameId,
      hwid: hwid != null ? String(hwid).slice(0, 200) : session.hwid,
      lastIp: ipAddress != null ? String(ipAddress).slice(0, 100) : session.lastIp,
      lastSeenAt: new Date(),
    },
  });
  const userMeta = await prisma.user.findUnique({ where: { id: userId }, select: { discordId: true } });
  await logScriptExecution(config, payload, {
    discordId: userMeta?.discordId || null,
    robloxUserId: updated.robloxUserId || null,
    robloxUsername: updated.robloxUsername || null,
    placeId: updated.robloxPlaceId || null,
    gameId: updated.robloxGameId || null,
    ipAddress: updated.lastIp || null,
    hwid: updated.hwid || null,
  });
  const accentRaw = accentPrimary != null ? String(accentPrimary).trim() : "";
  if (/^\d{1,3},\d{1,3},\d{1,3}$/.test(accentRaw)) {
    liveAccentByUserId.set(userId, accentRaw);
  }
  return { userId };
}

const COMMAND_TTL_MS = 5 * 60_000;
const DELIVER_RETRY_MS = 15_000;
const MAX_DELIVERY_ATTEMPTS = 60;

async function enqueueClientCommand(userId, action, payload = null) {
  return prisma.clientCommand.create({
    data: {
      userId,
      action,
      payload: payload || undefined,
      expiresAt: new Date(Date.now() + COMMAND_TTL_MS),
    },
  });
}

export async function fetchPendingClientCommands(token) {
  const payload = await validateToken(token);
  const userId = Number(payload.sub);
  const now = new Date();

  await prisma.clientCommand.updateMany({
    where: {
      userId,
      status: { in: ["pending", "delivered"] },
      OR: [
        { expiresAt: { lte: now } },
        { attempts: { gte: MAX_DELIVERY_ATTEMPTS } },
      ],
    },
    data: { status: "expired" },
  });

  const retryBefore = new Date(Date.now() - DELIVER_RETRY_MS);
  const rows = await prisma.clientCommand.findMany({
    where: {
      userId,
      status: { in: ["pending", "delivered"] },
      expiresAt: { gt: now },
      OR: [
        { status: "pending" },
        { status: "delivered", lastDeliveredAt: null },
        { status: "delivered", lastDeliveredAt: { lte: retryBefore } },
      ],
    },
    orderBy: { createdAt: "asc" },
    take: 10,
  });

  if (rows.length > 0) {
    const ids = rows.map((r) => r.id);
    await prisma.clientCommand.updateMany({
      where: { id: { in: ids } },
      data: {
        status: "delivered",
        lastDeliveredAt: now,
        attempts: { increment: 1 },
      },
    });
  }

  return rows.map((r) => ({
    id: r.id,
    action: r.action,
    payload: r.payload && typeof r.payload === "object" ? r.payload : null,
  }));
}

export async function ackClientCommand(token, commandId, ackStatus = "ok", ackError = null) {
  const payload = await validateToken(token);
  const userId = Number(payload.sub);
  const id = Number(commandId);
  if (!Number.isFinite(id)) throw new Error("Invalid command id");
  const cmd = await prisma.clientCommand.findUnique({ where: { id } });
  if (!cmd || cmd.userId !== userId) throw new Error("Command not found");
  await prisma.clientCommand.update({
    where: { id },
    data: {
      status: "acknowledged",
      acknowledgedAt: new Date(),
      ackStatus: String(ackStatus || "ok").slice(0, 32),
      ackError: ackError ? String(ackError).slice(0, 500) : null,
    },
  });
}

// Keep this generous so temporary network hiccups or brief executor stalls
// don't cause false "not live" failures for /kick and /message.
const PRESENCE_MAX_AGE_MS = 15 * 60_000;
// Peer roster / peer actions must be much fresher to avoid stale "online" users.
const PEER_PRESENCE_MAX_AGE_MS = 12 * 1000;

async function assertUserInGameWithScript(userId) {
  const cutoff = new Date(Date.now() - PRESENCE_MAX_AGE_MS);
  const session = await prisma.session.findFirst({
    where: {
      userId,
      endedAt: null,
      revoked: false,
      lastSeenAt: { gte: cutoff },
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
  const user = await getUserByIdentity(discordId);
  await assertUserInGameWithScript(user.id);
  const cmd = await enqueueClientCommand(user.id, "kick");
  return { username: user.username, commandId: cmd.id };
}

export async function enqueueMessageByDiscordId(discordId, message, options = {}) {
  const text = (message || "").trim();
  if (!text) throw new Error("Message required");
  if (text.length > 500) throw new Error("Message too long (max 500)");

  const user = await getUserByIdentity(discordId);
  await assertUserInGameWithScript(user.id);
  const senderName = String(options.senderName || "").trim();
  const anonymous = options.anonymous !== false;
  const cmd = await enqueueClientCommand(user.id, "message", {
    title: "Message received",
    body: text,
    sender: anonymous ? null : (senderName || "Unknown sender"),
    accent: "primary",
    autoCloseSec: 15,
  });
  return { username: user.username, commandId: cmd.id };
}

export async function enqueueMessageToAllLive(message, options = {}) {
  const text = (message || "").trim();
  if (!text) throw new Error("Message required");
  if (text.length > 500) throw new Error("Message too long (max 500)");

  const senderName = String(options.senderName || "").trim();
  const anonymous = options.anonymous !== false;
  const cutoff = new Date(Date.now() - PEER_PRESENCE_MAX_AGE_MS);
  const rows = await prisma.session.findMany({
    where: {
      endedAt: null,
      revoked: false,
      lastSeenAt: { gte: cutoff },
    },
    orderBy: { lastSeenAt: "desc" },
    include: {
      user: { select: { id: true, username: true } },
    },
    take: 500,
  });

  const latestByUser = new Map();
  for (const s of rows) {
    if (!latestByUser.has(s.userId)) latestByUser.set(s.userId, s);
  }
  const sessions = Array.from(latestByUser.values());
  if (sessions.length === 0) throw new Error("No live UniversalAdmin users found");

  const commandIds = [];
  const usernames = [];
  for (const s of sessions) {
    const cmd = await enqueueClientCommand(s.userId, "message", {
      title: "Message received",
      body: text,
      sender: anonymous ? null : (senderName || "Unknown sender"),
      accent: "primary",
      autoCloseSec: 15,
    });
    commandIds.push(cmd.id);
    usernames.push(s.user?.username || `user:${s.userId}`);
  }
  return { count: commandIds.length, commandIds, usernames };
}

async function hasLiveScriptPresence(userId, maxAgeMs = PRESENCE_MAX_AGE_MS) {
  const cutoff = new Date(Date.now() - maxAgeMs);
  const session = await prisma.session.findFirst({
    where: {
      userId,
      endedAt: null,
      revoked: false,
      lastSeenAt: { gte: cutoff },
    },
    orderBy: { lastSeenAt: "desc" },
  });
  return !!session;
}

async function getEffectiveTierForUser(user) {
  const active = await getBestActiveLicense(user.id);
  if (active?.tier) return active.tier;
  if (user.rank && TIER_WEIGHT[user.rank]) return user.rank;
  return "Member";
}

async function findLiveSessionForUser(userId, maxAgeMs = PRESENCE_MAX_AGE_MS) {
  const cutoff = new Date(Date.now() - maxAgeMs);
  return prisma.session.findFirst({
    where: {
      userId,
      endedAt: null,
      revoked: false,
      lastSeenAt: { gte: cutoff },
    },
    orderBy: { lastSeenAt: "desc" },
    include: {
      user: { select: { id: true, username: true, rank: true } },
    },
  });
}

async function resolvePeerTargetUser(requester, targetIdentity) {
  try {
    const byIdentity = await getUserByIdentity(targetIdentity);
    return byIdentity;
  } catch {
    // Fallback to Roblox identity of currently-live users in requester's server.
  }

  const raw = String(targetIdentity || "").trim();
  if (!raw) throw new Error("User identity required");
  const requesterLive = await findLiveSessionForUser(requester.id, PEER_PRESENCE_MAX_AGE_MS);
  if (!requesterLive || !requesterLive.robloxGameId) {
    throw new Error("Requester is not live in a Roblox game");
  }

  const candidates = await prisma.session.findMany({
    where: {
      endedAt: null,
      revoked: false,
      lastSeenAt: { gte: new Date(Date.now() - PEER_PRESENCE_MAX_AGE_MS) },
      robloxGameId: requesterLive.robloxGameId,
      OR: [
        { robloxUserId: raw },
        { robloxUsername: { equals: raw, mode: "insensitive" } },
      ],
    },
    orderBy: { lastSeenAt: "desc" },
    include: {
      user: true,
    },
    take: 5,
  });

  if (!candidates.length) {
    throw new Error("Target not found in your live server by Roblox username/userId");
  }
  return candidates[0].user;
}

export async function listOnlinePeers(token, { placeId = null, gameId = null } = {}) {
  const payload = await validateToken(token);
  const requesterId = Number(payload.sub);
  const requesterLive = await findLiveSessionForUser(requesterId, PEER_PRESENCE_MAX_AGE_MS);
  if (!requesterLive) {
    return { peers: [] };
  }

  const targetGameId = gameId != null ? String(gameId) : (requesterLive.robloxGameId || null);
  const targetPlaceId = placeId != null ? String(placeId) : (requesterLive.robloxPlaceId || null);
  const cutoff = new Date(Date.now() - PEER_PRESENCE_MAX_AGE_MS);
  const where = {
    endedAt: null,
    revoked: false,
    lastSeenAt: { gte: cutoff },
    ...(targetGameId ? { robloxGameId: targetGameId } : {}),
    ...(targetPlaceId ? { robloxPlaceId: targetPlaceId } : {}),
  };

  const rows = await prisma.session.findMany({
    where,
    orderBy: { lastSeenAt: "desc" },
    include: {
      user: { select: { id: true, username: true, rank: true } },
    },
    take: 200,
  });

  const latestByUser = new Map();
  for (const s of rows) {
    if (!latestByUser.has(s.userId)) {
      latestByUser.set(s.userId, s);
    }
  }
  const peers = await Promise.all(
    Array.from(latestByUser.values()).map(async (s) => {
      const tier = await getEffectiveTierForUser(s.user);
      return {
        userId: s.userId,
        username: s.user.username,
        tier,
        accentPrimary: liveAccentByUserId.get(s.userId) || null,
        robloxUserId: s.robloxUserId || null,
        robloxUsername: s.robloxUsername || null,
        placeId: s.robloxPlaceId || null,
        gameId: s.robloxGameId || null,
        lastSeenAt: s.lastSeenAt || null,
      };
    })
  );
  return { peers };
}

export async function enqueuePeerClientAction(token, { targetIdentity, action, payload = {} }) {
  const requesterPayload = await validateToken(token);
  const requester = await prisma.user.findUnique({ where: { id: Number(requesterPayload.sub) } });
  if (!requester) throw new Error("Requester not found");
  const requesterTier = await getEffectiveTierForUser(requester);
  if (!hasTierAtLeast(requesterTier, "Premium")) {
    throw new Error("Premium required");
  }

  const target = await resolvePeerTargetUser(requester, targetIdentity);
  if (target.id === requester.id) throw new Error("Cannot target yourself");
  const targetTier = await getEffectiveTierForUser(target);
  if (targetTier === "Owner") throw new Error("Owner users cannot be targeted");
  if (!(await hasLiveScriptPresence(target.id, PEER_PRESENCE_MAX_AGE_MS))) {
    throw new Error("Target is not live with UniversalAdmin");
  }

  const normalized = String(action || "").trim().toLowerCase();
  if (
    normalized !== "ua_bring" &&
    normalized !== "ua_freeze" &&
    normalized !== "ua_fling" &&
    normalized !== "ua_loopfling" &&
    normalized !== "ua_loopfling_start" &&
    normalized !== "ua_loopfling_stop" &&
    normalized !== "ua_kill"
  ) {
    throw new Error("Unsupported peer action");
  }

  const cmd = await enqueueClientCommand(target.id, normalized, {
    fromUserId: requester.id,
    fromUsername: requester.username,
    fromTier: requesterTier,
    ...payload,
  });
  return { commandId: cmd.id, targetUsername: target.username };
}

export async function enqueueWarnByIdentity(identity, message, options = {}) {
  const text = (message || "").trim();
  if (!text) throw new Error("Warning message required");
  if (text.length > 500) throw new Error("Warning too long (max 500)");
  const user = await getUserByIdentity(identity);
  const senderName = String(options.senderName || "").trim();
  const anonymous = options.anonymous !== false;
  const warning = await prisma.warning.create({
    data: {
      userId: user.id,
      message: text,
      issuedByDiscordId: options.issuedByDiscordId ? String(options.issuedByDiscordId) : null,
      issuedByName: anonymous ? null : (senderName || null),
    },
  });
  let commandId = null;
  if (await hasLiveScriptPresence(user.id)) {
    const cmd = await enqueueClientCommand(user.id, "warn", {
      title: "Warning Issued",
      body: text,
      sender: anonymous ? null : (senderName || "Unknown sender"),
      accent: "danger",
      autoCloseSec: 15,
      warningId: warning.id,
    });
    commandId = cmd.id;
  }
  return { username: user.username, commandId, warningId: warning.id, deliveredLive: !!commandId };
}

export async function listWarningsByIdentity(identity) {
  const user = await getUserByIdentity(identity);
  const warnings = await prisma.warning.findMany({
    where: { userId: user.id },
    orderBy: { createdAt: "desc" },
    take: 50,
  });
  return { username: user.username, warnings };
}

export async function getPresenceStatusByIdentity(identity) {
  const user = await getUserByIdentity(identity);
  const latestSession = await prisma.session.findFirst({
    where: { userId: user.id, endedAt: null, revoked: false },
    orderBy: { lastSeenAt: "desc" },
  });
  const pending = await prisma.clientCommand.count({
    where: { userId: user.id, status: { in: ["pending", "delivered"] }, expiresAt: { gt: new Date() } },
  });
  const lastAck = await prisma.clientCommand.findFirst({
    where: { userId: user.id, status: "acknowledged" },
    orderBy: { acknowledgedAt: "desc" },
  });
  const recentCutoff = new Date(Date.now() - PRESENCE_MAX_AGE_MS);
  return {
    username: user.username,
    linkedDiscordId: user.discordId || null,
    live: !!(latestSession && latestSession.lastSeenAt && latestSession.lastSeenAt >= recentCutoff),
    lastSeenAt: latestSession?.lastSeenAt || null,
    robloxUsername: latestSession?.robloxUsername || null,
    robloxUserId: latestSession?.robloxUserId || null,
    placeId: latestSession?.robloxPlaceId || null,
    ipAddress: latestSession?.lastIp || null,
    hwid: latestSession?.hwid || null,
    pendingCommands: pending,
    lastAckAt: lastAck?.acknowledgedAt || null,
    lastAckStatus: lastAck?.ackStatus || null,
    lastAckError: lastAck?.ackError || null,
  };
}
