import "dotenv/config";

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing env var: ${name}`);
  return value;
}

export const config = {
  discordToken: required("DISCORD_TOKEN"),
  discordClientId: required("DISCORD_CLIENT_ID"),
  discordGuildId: required("DISCORD_GUILD_ID"),
  // Railway/Render set PORT; local dev can use API_PORT or default 3000.
  apiPort: Number(process.env.PORT || process.env.API_PORT || 3000),
  jwtSecret: required("JWT_SECRET"),
  adminDiscordIds: (process.env.ADMIN_DISCORD_IDS || "")
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean),
  // Fixed requested member role for registration flow.
  // If you want env override later, we can re-enable it.
  memberRoleId: "1493712567581806724",
  scriptLoaderUrl:
    process.env.SCRIPT_LOADER_URL ||
    "https://discord-key-auth-production.up.railway.app/UniversalAdmin.lua",
  joinLogsChannelId: process.env.JOIN_LOGS_CHANNEL_ID || "1494373966071201843",
  loginLogsChannelId: process.env.LOGIN_LOGS_CHANNEL_ID || "1494374135365767228",
};
