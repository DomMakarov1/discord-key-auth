let botClient = null;
const seenScriptJtis = new Set();

export function setLogClient(client) {
  botClient = client || null;
}

function clip(value, maxLen = 1024) {
  const text = String(value == null ? "n/a" : value);
  return text.length > maxLen ? `${text.slice(0, maxLen - 3)}...` : text;
}

function field(name, value, inline = true) {
  return { name, value: clip(value || "n/a"), inline };
}

async function sendChannelLog(channelId, embed) {
  if (!botClient || !channelId) return;
  try {
    const channel =
      (botClient.channels?.cache && botClient.channels.cache.get(channelId))
      || (await botClient.channels.fetch(channelId).catch(() => null));
    if (!channel || typeof channel.send !== "function") return;
    await channel.send({ embeds: [embed] });
  } catch (err) {
    console.warn("Failed to send Discord log:", err?.message || String(err));
  }
}

export async function logScriptExecution(config, payload, details = {}) {
  const jti = String(payload?.jti || "");
  if (!jti || seenScriptJtis.has(jti)) return;
  seenScriptJtis.add(jti);

  const embed = {
    title: "Script Executed",
    color: 0x22c55e,
    fields: [
      field("Script User", `\`${payload?.username || "unknown"}\``),
      field("Tier", `\`${payload?.tier || "n/a"}\``),
      field("Discord ID", `\`${details.discordId || "n/a"}\``),
      field("Roblox Username", `\`${details.robloxUsername || "n/a"}\``),
      field("Roblox User ID", `\`${details.robloxUserId || "n/a"}\``),
      field("Place ID", `\`${details.placeId || "n/a"}\``),
      field("Game ID", `\`${details.gameId || "n/a"}\``),
      field("IP", `\`${details.ipAddress || "n/a"}\``),
      field("HWID", `\`${details.hwid || "n/a"}\``, false),
      field("Session JTI", `\`${jti}\``, false),
    ],
    timestamp: new Date().toISOString(),
  };
  await sendChannelLog(config.joinLogsChannelId, embed);
}

export async function logScriptLogin(config, payload, details = {}) {
  const embed = {
    title: "Script Login",
    color: 0x3b82f6,
    fields: [
      field("Script User", `\`${payload?.username || "unknown"}\``),
      field("Tier", `\`${payload?.tier || "n/a"}\``),
      field("Method", `\`${details.method || "unknown"}\``),
      field("Discord ID", `\`${details.discordId || "n/a"}\``),
      field("Key", `\`${details.keyCode || "n/a"}\``),
      field("Session JTI", `\`${payload?.jti || "n/a"}\``, false),
    ],
    timestamp: new Date().toISOString(),
  };
  await sendChannelLog(config.loginLogsChannelId, embed);
}
