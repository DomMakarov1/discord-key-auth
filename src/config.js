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
  memberRoleId: process.env.MEMBER_ROLE_ID || "1493712567581806724",
  scriptLoaderUrl:
    process.env.SCRIPT_LOADER_URL ||
    "https://discord-key-auth-production.up.railway.app/UniversalAdmin.lua",
};
