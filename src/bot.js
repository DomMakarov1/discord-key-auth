import {
  Client,
  GatewayIntentBits,
  REST,
  Routes,
  SlashCommandBuilder,
  EmbedBuilder,
} from "discord.js";
import { config } from "./config.js";
import {
  assignKey,
  changePassword,
  extendUser,
  getSessions,
  issueBulk,
  issueKey,
  listKeys,
  logoutAllSessions,
  redeemKey,
  registerUser,
  resetPassword,
  revokeUser,
  setBlacklist,
  setTier,
  statusUser,
  deleteAccount,
  transferDiscord,
  unlinkDiscord,
  enqueueKickByDiscordId,
  enqueueMessageByDiscordId,
  enqueueMessageToAllLive,
  enqueueWarnByIdentity,
  listWarningsByIdentity,
  getPresenceStatusByIdentity,
  addAccessBan,
  removeAccessBans,
  removeAccessBansForUserIdentity,
  banFromUserLatestSession,
} from "./auth.js";

const commands = [
  new SlashCommandBuilder()
    .setName("register")
    .setDescription("Register account for script auth")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true))
    .addStringOption((o) => o.setName("pass").setDescription("Password").setRequired(true)),
  new SlashCommandBuilder()
    .setName("key")
    .setDescription("Redeem an issued key")
    .addStringOption((o) => o.setName("code").setDescription("Key code").setRequired(true)),
  new SlashCommandBuilder()
    .setName("issue")
    .setDescription("Admin: issue a key")
    .addIntegerOption((o) =>
      o.setName("days").setDescription("Duration in days").setRequired(true).setMinValue(1)
    )
    .addStringOption((o) =>
      o
        .setName("tier")
        .setDescription("Key tier")
        .setRequired(true)
        .addChoices(
          { name: "Premium", value: "Premium" },
          { name: "Owner", value: "Owner" }
        )
    ),
  new SlashCommandBuilder()
    .setName("status")
    .setDescription("Admin: get user status")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true)),
  new SlashCommandBuilder()
    .setName("extend")
    .setDescription("Admin: extend user license")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true))
    .addIntegerOption((o) => o.setName("days").setDescription("Days").setRequired(true).setMinValue(1)),
  new SlashCommandBuilder()
    .setName("revoke")
    .setDescription("Admin: revoke user license")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true)),
  new SlashCommandBuilder()
    .setName("deleteaccount")
    .setDescription("Admin: permanently delete a user account")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true)),
  new SlashCommandBuilder()
    .setName("resetpass")
    .setDescription("Admin: reset user password")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true))
    .addStringOption((o) => o.setName("newpass").setDescription("New password").setRequired(true)),
  new SlashCommandBuilder().setName("whoami").setDescription("Admin: show linked account"),
  new SlashCommandBuilder()
    .setName("transfer")
    .setDescription("Admin: transfer account link to target Discord ID")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true))
    .addStringOption((o) =>
      o.setName("targetdiscordid").setDescription("Target Discord ID").setRequired(true)
    ),
  new SlashCommandBuilder()
    .setName("assignkey")
    .setDescription("Admin: assign key to user")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true))
    .addStringOption((o) => o.setName("key").setDescription("Key code").setRequired(true)),
  new SlashCommandBuilder()
    .setName("listkeys")
    .setDescription("List keys")
    .addStringOption((o) => o.setName("user").setDescription("Username (admin only)"))
    .addIntegerOption((o) =>
      o.setName("page").setDescription("Page number").setMinValue(1)
    )
    .addStringOption((o) =>
      o
        .setName("filter")
        .setDescription("used or unused")
        .addChoices(
          { name: "used", value: "used" },
          { name: "unused", value: "unused" },
          { name: "all", value: "all" }
        )
    ),
  new SlashCommandBuilder()
    .setName("blacklist")
    .setDescription("Admin: blacklist user (infinite or timed, e.g. 5h / 10d)")
    .addStringOption((o) => o.setName("user").setDescription("Username or Discord @/id").setRequired(true))
    .addStringOption((o) =>
      o
        .setName("duration")
        .setDescription("infinite, 5h, 10d")
        .setRequired(true)
    ),
  new SlashCommandBuilder()
    .setName("unblacklist")
    .setDescription("Admin: unblacklist user")
    .addStringOption((o) => o.setName("user").setDescription("Username or Discord @/id").setRequired(true)),
  new SlashCommandBuilder()
    .setName("sessions")
    .setDescription("Admin: view user sessions")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true))
    .addStringOption((o) =>
      o
        .setName("scope")
        .setDescription("current/previous/all")
        .setRequired(true)
        .addChoices(
          { name: "current", value: "current" },
          { name: "previous", value: "previous" },
          { name: "all", value: "all" }
        )
    )
    .addIntegerOption((o) =>
      o.setName("page").setDescription("Page number").setMinValue(1)
    ),
  new SlashCommandBuilder()
    .setName("logoutall")
    .setDescription("Admin: logout all user sessions")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true)),
  new SlashCommandBuilder()
    .setName("issuebulk")
    .setDescription("Admin: issue multiple keys")
    .addIntegerOption((o) => o.setName("days").setDescription("Duration in days").setRequired(true).setMinValue(1))
    .addIntegerOption((o) => o.setName("count").setDescription("How many keys").setRequired(true).setMinValue(1).setMaxValue(200))
    .addStringOption((o) =>
      o
        .setName("tier")
        .setDescription("Key tier")
        .setRequired(true)
        .addChoices(
          { name: "Premium", value: "Premium" },
          { name: "Owner", value: "Owner" }
        )
    ),
  new SlashCommandBuilder()
    .setName("settier")
    .setDescription("Admin: set user rank")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true))
    .addStringOption((o) =>
      o
        .setName("rank")
        .setDescription("Rank")
        .setRequired(true)
        .addChoices(
          { name: "Member", value: "Member" },
          { name: "Premium", value: "Premium" },
          { name: "Owner", value: "Owner" }
        )
    ),
  new SlashCommandBuilder()
    .setName("changepass")
    .setDescription("User: change your password")
    .addStringOption((o) => o.setName("old").setDescription("Old password").setRequired(true))
    .addStringOption((o) => o.setName("new").setDescription("New password").setRequired(true)),
  new SlashCommandBuilder().setName("unlink").setDescription("User: unlink your Discord account"),
  new SlashCommandBuilder()
    .setName("kick")
    .setDescription("Admin: kick user by script username or Discord @/id")
    .addStringOption((o) =>
      o.setName("target").setDescription("Script username or Discord @mention/id").setRequired(true)
    ),
  new SlashCommandBuilder()
    .setName("message")
    .setDescription("Admin: message user by script username or Discord @/id")
    .addStringOption((o) =>
      o.setName("text").setDescription("Message text").setRequired(true).setMaxLength(500)
    )
    .addStringOption((o) =>
      o.setName("target").setDescription("Script username or Discord @mention/id").setRequired(true)
    )
    .addBooleanOption((o) =>
      o.setName("anonymous").setDescription("Hide sender identity (default true)").setRequired(false)
    ),
  new SlashCommandBuilder()
    .setName("warn")
    .setDescription("Admin: issue a warning popup to a user")
    .addStringOption((o) =>
      o.setName("text").setDescription("Warning text").setRequired(true).setMaxLength(500)
    )
    .addStringOption((o) =>
      o.setName("target").setDescription("Script username or Discord @mention/id").setRequired(true)
    )
    .addBooleanOption((o) =>
      o.setName("anonymous").setDescription("Hide sender identity (default true)").setRequired(false)
    ),
  new SlashCommandBuilder()
    .setName("warnlist")
    .setDescription("Admin: list warnings for a user")
    .addStringOption((o) =>
      o.setName("user").setDescription("Username or Discord @/id").setRequired(true)
    ),
  new SlashCommandBuilder()
    .setName("presence")
    .setDescription("Admin: inspect script heartbeat/queue status")
    .addStringOption((o) =>
      o.setName("user").setDescription("Username or Discord @/id").setRequired(true)
    ),
  new SlashCommandBuilder()
    .setName("script")
    .setDescription("Get the latest UniversalAdmin loadstring"),
  new SlashCommandBuilder()
    .setName("hwidban")
    .setDescription("Admin: block script login for an HWID")
    .addStringOption((o) => o.setName("hwid").setDescription("HWID string").setRequired(true))
    .addStringOption((o) => o.setName("reason").setDescription("Optional reason")),
  new SlashCommandBuilder()
    .setName("ipban")
    .setDescription("Admin: block script login for an IP address")
    .addStringOption((o) => o.setName("ip").setDescription("IPv4/IPv6").setRequired(true))
    .addStringOption((o) => o.setName("reason").setDescription("Optional reason")),
  new SlashCommandBuilder()
    .setName("fullban")
    .setDescription("Admin: block script login for user's latest HWID + IP (from presence)")
    .addStringOption((o) =>
      o.setName("user").setDescription("Username or Discord @/id").setRequired(true)
    )
    .addStringOption((o) => o.setName("reason").setDescription("Optional reason")),
  new SlashCommandBuilder()
    .setName("unban")
    .setDescription("Admin: remove access bans by HWID, IP, or user's last known HWID/IP")
    .addStringOption((o) => o.setName("hwid").setDescription("HWID to unban"))
    .addStringOption((o) => o.setName("ip").setDescription("IP to unban"))
    .addStringOption((o) =>
      o.setName("user").setDescription("Unban last known HWID + IP for this account")
    ),
].map((c) => c.toJSON());

function isAdmin(id) {
  return config.adminDiscordIds.includes(id);
}

function requireAdmin(interaction) {
  if (!isAdmin(interaction.user.id)) {
    throw new Error("Not authorized");
  }
}

function fmtKey(k) {
  const used = k.redeemedAt ? "used" : "unused";
  const assignee = k.assignedToId ? `assigned:${k.assignedToId}` : "unassigned";
  return `\`${k.code}\`\nTier: **${k.tier}** · ${used.toUpperCase()} · ${assignee}\nCreated: ${new Date(k.createdAt).toISOString()}`;
}

function fmtSession(s) {
  const end = s.endedAt ? new Date(s.endedAt).toISOString() : "active";
  const durMs = (s.endedAt ? new Date(s.endedAt) : new Date()) - new Date(s.startedAt);
  const mins = Math.max(1, Math.floor(durMs / 60000));
  return `Session **#${s.id}**\nStart: ${new Date(s.startedAt).toISOString()}\nEnd: ${end}\nDuration: ${mins} min\nRoblox User: ${s.robloxUserId || "n/a"}\nGame: ${s.robloxGameId || "n/a"}\nState: ${s.endedAt ? "Ended" : "Active"}`;
}

async function replyPagedEmbed(interaction, title, items, page, formatter) {
  const perPage = 6;
  const totalPages = Math.max(1, Math.ceil(items.length / perPage));
  const currentPage = Math.min(Math.max(page || 1, 1), totalPages);
  const start = (currentPage - 1) * perPage;
  const chunk = items.slice(start, start + perPage);

  const embed = new EmbedBuilder()
    .setColor(0x5865f2)
    .setTitle(title)
    .setFooter({ text: `Page ${currentPage}/${totalPages} · ${items.length} total` })
    .setTimestamp(new Date());

  if (chunk.length === 0) {
    embed.setDescription("No entries found.");
  } else {
    chunk.forEach((item, idx) => {
      embed.addFields({
        name: `Entry ${start + idx + 1}`,
        value: formatter(item).slice(0, 1024),
      });
    });
  }

  await interaction.reply({ embeds: [embed], ephemeral: true });
}

export async function startBot() {
  const rest = new REST({ version: "10" }).setToken(config.discordToken);
  // Register once globally only. Registering the same commands globally AND on a guild
  // makes every slash appear twice for members in that server.
  if (config.discordGuildId) {
    await rest.put(Routes.applicationGuildCommands(config.discordClientId, config.discordGuildId), {
      body: [],
    });
  }
  await rest.put(Routes.applicationCommands(config.discordClientId), { body: commands });
  console.log("Registered slash commands globally (guild + DMs; updates may take up to ~1h to propagate).");

  const client = new Client({ intents: [GatewayIntentBits.Guilds] });

  async function assignMemberRoleByConfig(discordUserId, interaction) {
    if (!config.memberRoleId) {
      return { ok: false, reason: "member role id not configured" };
    }
    try {
      const guildFromInteraction = interaction?.guild || null;
      const guildFromConfig = config.discordGuildId
        ? ((client.guilds.cache && client.guilds.cache.get(config.discordGuildId))
          || (await client.guilds.fetch(config.discordGuildId).catch(() => null)))
        : null;
      const guild = guildFromInteraction || guildFromConfig;
      if (!guild) return { ok: false, reason: "target guild not found" };

      const role = await guild.roles.fetch(config.memberRoleId).catch(() => null);
      if (!role) {
        return { ok: false, reason: `role ${config.memberRoleId} not found in guild ${guild.id}` };
      }

      const member = await guild.members.fetch(discordUserId);
      if (!member) return { ok: false, reason: "member not found in target guild" };
      await member.roles.add(config.memberRoleId);
      return { ok: true, reason: null };
    } catch (err) {
      console.warn("Role assignment failed", {
        guildId: interaction?.guildId || config.discordGuildId,
        memberRoleId: config.memberRoleId,
        discordUserId,
        error: err?.message || String(err),
      });
      return { ok: false, reason: err?.message || String(err) };
    }
  }

  client.once("ready", () => {
    console.log(`Discord bot ready as ${client.user.tag}`);
  });

  client.on("interactionCreate", async (interaction) => {
    if (!interaction.isChatInputCommand()) return;

    try {
      if (interaction.commandName === "register") {
        const username = interaction.options.getString("user", true);
        const password = interaction.options.getString("pass", true);
        await registerUser({ username, password, discordId: interaction.user.id });
        const roleAssign = await assignMemberRoleByConfig(interaction.user.id, interaction);
        await interaction.reply({
          content: roleAssign.ok
            ? `Registered \`${username}\` and role assigned`
            : `Registered \`${username}\` (role not assigned automatically: ${roleAssign.reason})`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "key") {
        const code = interaction.options.getString("code", true);
        const out = await redeemKey({ discordId: interaction.user.id, code });
        await interaction.reply({
          content: `Key redeemed. Tier: ${out.tier}, expires: ${out.expiresAt.toISOString()}`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "issue") {
        requireAdmin(interaction);
        const days = interaction.options.getInteger("days", true);
        const tier = interaction.options.getString("tier", true);
        const key = await issueKey({ tier, durationDays: days });
        await interaction.reply({ content: `Issued ${tier} key: \`${key.code}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "status") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const out = await statusUser(username);
        const exp = out.license ? out.license.expiresAt.toISOString() : "none";
        await interaction.reply({
          content: `user:\`${out.user.username}\` rank:${out.user.rank} blacklisted:${out.user.blacklisted} license_exp:${exp}`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "extend") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const days = interaction.options.getInteger("days", true);
        const lic = await extendUser(username, days);
        await interaction.reply({ content: `Extended \`${username}\` to ${lic.expiresAt.toISOString()}`, ephemeral: true });
        return;
      }

      if (interaction.commandName === "revoke") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        await revokeUser(username);
        await interaction.reply({ content: `Revoked active license for \`${username}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "deleteaccount") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const out = await deleteAccount(username);
        await interaction.reply({
          content: `Deleted account \`${out.username}\` and removed linked sessions/licenses.`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "resetpass") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const newPass = interaction.options.getString("newpass", true);
        await resetPassword(username, newPass);
        await interaction.reply({ content: `Password reset for \`${username}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "whoami") {
        requireAdmin(interaction);
        await interaction.reply({
          content: `discord:\`${interaction.user.id}\` admin:${isAdmin(interaction.user.id)}`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "transfer") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const targetDiscordId = interaction.options.getString("targetdiscordid", true);
        await transferDiscord(username, targetDiscordId);
        await interaction.reply({ content: `Transferred \`${username}\` -> \`${targetDiscordId}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "assignkey") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const code = interaction.options.getString("key", true);
        await assignKey(username, code);
        await interaction.reply({ content: `Assigned key to \`${username}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "listkeys") {
        const usernameOpt = interaction.options.getString("user");
        const filter = interaction.options.getString("filter") || "all";
        const page = interaction.options.getInteger("page") || 1;
        let username = null;
        let discordId = interaction.user.id;
        if (usernameOpt) {
          requireAdmin(interaction);
          username = usernameOpt;
          discordId = null;
        }
        const keys = await listKeys({ username, discordId, filter });
        await replyPagedEmbed(interaction, "Key List", keys, page, fmtKey);
        return;
      }

      if (interaction.commandName === "blacklist") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const duration = interaction.options.getString("duration", true);
        const out = await setBlacklist(username, true, duration);
        const untilText = out.blacklistedUntil
          ? new Date(out.blacklistedUntil).toISOString()
          : "infinite";
        await interaction.reply({
          content: `Blacklisted \`${out.username}\` until **${untilText}**`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "unblacklist") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const out = await setBlacklist(username, false);
        await interaction.reply({ content: `Unblacklisted \`${out.username}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "sessions") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const scope = interaction.options.getString("scope", true);
        const page = interaction.options.getInteger("page") || 1;
        const sessions = await getSessions(username, scope);
        await replyPagedEmbed(interaction, `Sessions · ${username}`, sessions, page, fmtSession);
        return;
      }

      if (interaction.commandName === "logoutall") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        await logoutAllSessions(username);
        await interaction.reply({ content: `Logged out all sessions for \`${username}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "issuebulk") {
        requireAdmin(interaction);
        const days = interaction.options.getInteger("days", true);
        const count = interaction.options.getInteger("count", true);
        const tier = interaction.options.getString("tier", true);
        const keys = await issueBulk(days, count, tier);
        await interaction.reply({
          content: `Issued ${keys.length} ${tier} keys:\n${keys.slice(0, 20).map((k) => `\`${k.code}\``).join("\n")}`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "settier") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        const rank = interaction.options.getString("rank", true);
        await setTier(username, rank);
        await interaction.reply({ content: `Set \`${username}\` rank to \`${rank}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "changepass") {
        const oldPass = interaction.options.getString("old", true);
        const newPass = interaction.options.getString("new", true);
        await changePassword(interaction.user.id, oldPass, newPass);
        await interaction.reply({ content: "Password changed", ephemeral: true });
        return;
      }

      if (interaction.commandName === "unlink") {
        await unlinkDiscord(interaction.user.id);
        await interaction.reply({ content: "Discord account unlinked", ephemeral: true });
        return;
      }

      if (interaction.commandName === "kick") {
        requireAdmin(interaction);
        const targetText = interaction.options.getString("target");
        const identity = targetText;
        const out = await enqueueKickByDiscordId(identity);
        await interaction.reply({
          content: `Kick queued for **${out.username}** (command #${out.commandId}).`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "message") {
        requireAdmin(interaction);
        const targetText = interaction.options.getString("target");
        const identity = targetText;
        const text = interaction.options.getString("text", true);
        const anonymous = interaction.options.getBoolean("anonymous");
        if (String(targetText || "").trim().toLowerCase() === "all") {
          const outAll = await enqueueMessageToAllLive(text, {
            anonymous: anonymous !== false,
            senderName: interaction.user.username,
            issuedByDiscordId: interaction.user.id,
          });
          const preview = outAll.usernames.slice(0, 8).join(", ");
          await interaction.reply({
            content:
              `Broadcast queued for **${outAll.count}** live users.` +
              (preview ? ` Targets: ${preview}${outAll.usernames.length > 8 ? "..." : ""}` : ""),
            ephemeral: true,
          });
          return;
        }
        const out = await enqueueMessageByDiscordId(identity, text, {
          anonymous: anonymous !== false,
          senderName: interaction.user.username,
          issuedByDiscordId: interaction.user.id,
        });
        await interaction.reply({
          content: `Message queued for **${out.username}** (command #${out.commandId}).`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "warn") {
        requireAdmin(interaction);
        const targetText = interaction.options.getString("target");
        const text = interaction.options.getString("text", true);
        const anonymous = interaction.options.getBoolean("anonymous");
        const out = await enqueueWarnByIdentity(targetText, text, {
          anonymous: anonymous !== false,
          senderName: interaction.user.username,
          issuedByDiscordId: interaction.user.id,
        });
        await interaction.reply({
          content: out.deliveredLive
            ? `Warning saved for **${out.username}** (#${out.warningId}) and live popup queued (command #${out.commandId}).`
            : `Warning saved for **${out.username}** (#${out.warningId}). User is offline/not running script, so no live popup queued.`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "warnlist") {
        requireAdmin(interaction);
        const identity = interaction.options.getString("user", true);
        const out = await listWarningsByIdentity(identity);
        if (!out.warnings.length) {
          await interaction.reply({ content: `No warnings for \`${out.username}\`.`, ephemeral: true });
          return;
        }
        const lines = out.warnings.slice(0, 25).map((w) =>
          `#${w.id} · ${new Date(w.createdAt).toISOString()} · by:${w.issuedByName || w.issuedByDiscordId || "anonymous"}\n${w.message}`
        );
        await interaction.reply({
          content: `Warnings for \`${out.username}\`:\n` + lines.join("\n\n"),
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "presence") {
        requireAdmin(interaction);
        const identity = interaction.options.getString("user", true);
        const p = await getPresenceStatusByIdentity(identity);
        await interaction.reply({
          content:
            `user:\`${p.username}\` discord:\`${p.linkedDiscordId || "none"}\` live:${p.live}\n` +
            `last_seen:${p.lastSeenAt ? new Date(p.lastSeenAt).toISOString() : "none"} roblox_name:${p.robloxUsername || "n/a"} roblox_user:${p.robloxUserId || "n/a"} place:${p.placeId || "n/a"}\n` +
            `ip:${p.ipAddress || "n/a"} hwid:${p.hwid || "n/a"}\n` +
            `pending:${p.pendingCommands} last_ack:${p.lastAckAt ? new Date(p.lastAckAt).toISOString() : "none"} status:${p.lastAckStatus || "n/a"} err:${p.lastAckError || "n/a"}`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "script") {
        const loader = `loadstring(game:HttpGet("${config.scriptLoaderUrl}"))()`;
        await interaction.reply({
          content: [
            "Latest UniversalAdmin loader:",
            "```lua",
            loader,
            "```",
          ].join("\n"),
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "hwidban") {
        requireAdmin(interaction);
        const hwid = interaction.options.getString("hwid", true);
        const reason = interaction.options.getString("reason");
        await addAccessBan({
          hwid,
          reason,
          createdByDiscordId: interaction.user.id,
        });
        const short = hwid.length > 40 ? `${hwid.slice(0, 40)}…` : hwid;
        await interaction.reply({ content: `HWID ban added for \`${short}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "ipban") {
        requireAdmin(interaction);
        const ip = interaction.options.getString("ip", true);
        const reason = interaction.options.getString("reason");
        await addAccessBan({
          ip,
          reason,
          createdByDiscordId: interaction.user.id,
        });
        await interaction.reply({ content: `IP ban added for \`${ip}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "fullban") {
        requireAdmin(interaction);
        const user = interaction.options.getString("user", true);
        const reason = interaction.options.getString("reason");
        await banFromUserLatestSession(user, {
          reason,
          createdByDiscordId: interaction.user.id,
          mode: "full",
        });
        await interaction.reply({
          content: `Full access ban recorded for latest HWID+IP on \`${user}\`.`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "unban") {
        requireAdmin(interaction);
        const hwid = interaction.options.getString("hwid");
        const ip = interaction.options.getString("ip");
        const user = interaction.options.getString("user");
        let deleted;
        if (user && !hwid && !ip) {
          const out = await removeAccessBansForUserIdentity(user);
          deleted = out.deleted;
        } else {
          if (!hwid && !ip) {
            throw new Error("Provide hwid, ip, or user");
          }
          const out = await removeAccessBans({ hwid, ip });
          deleted = out.deleted;
        }
        await interaction.reply({
          content: `Removed **${deleted}** access ban row(s).`,
          ephemeral: true,
        });
        return;
      }
    } catch (err) {
      const msg = err?.message || "Unknown error";
      if (interaction.replied || interaction.deferred) {
        await interaction.followUp({ content: msg, ephemeral: true });
      } else {
        await interaction.reply({ content: msg, ephemeral: true });
      }
    }
  });

  await client.login(config.discordToken);
  return client;
}
