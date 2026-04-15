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
    .setDescription("Admin: issue a Member key")
    .addIntegerOption((o) =>
      o.setName("days").setDescription("Duration in days").setRequired(true).setMinValue(1)
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
    .setDescription("Admin: blacklist user")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true)),
  new SlashCommandBuilder()
    .setName("unblacklist")
    .setDescription("Admin: unblacklist user")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true)),
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
    .setDescription("Admin: issue multiple Member keys")
    .addIntegerOption((o) => o.setName("days").setDescription("Duration in days").setRequired(true).setMinValue(1))
    .addIntegerOption((o) => o.setName("count").setDescription("How many keys").setRequired(true).setMinValue(1).setMaxValue(200)),
  new SlashCommandBuilder()
    .setName("settier")
    .setDescription("Admin: set user rank")
    .addStringOption((o) => o.setName("user").setDescription("Username").setRequired(true))
    .addStringOption((o) =>
      o
        .setName("rank")
        .setDescription("Rank")
        .setRequired(true)
        .addChoices({ name: "Member", value: "Member" })
    ),
  new SlashCommandBuilder()
    .setName("changepass")
    .setDescription("User: change your password")
    .addStringOption((o) => o.setName("old").setDescription("Old password").setRequired(true))
    .addStringOption((o) => o.setName("new").setDescription("New password").setRequired(true)),
  new SlashCommandBuilder().setName("unlink").setDescription("User: unlink your Discord account"),
  new SlashCommandBuilder()
    .setName("kick")
    .setDescription("Admin: kick user by Discord @/id or script username")
    .addUserOption((o) =>
      o.setName("user").setDescription("Discord user target").setRequired(false)
    )
    .addStringOption((o) =>
      o.setName("target").setDescription("Script username or Discord id/mention").setRequired(false)
    ),
  new SlashCommandBuilder()
    .setName("message")
    .setDescription("Admin: message user by Discord @/id or script username")
    .addStringOption((o) =>
      o.setName("text").setDescription("Message text").setRequired(true).setMaxLength(500)
    )
    .addUserOption((o) =>
      o.setName("user").setDescription("Discord user target").setRequired(false)
    )
    .addStringOption((o) =>
      o.setName("target").setDescription("Script username or Discord id/mention").setRequired(false)
    ),
  new SlashCommandBuilder()
    .setName("script")
    .setDescription("Get the latest UniversalAdmin loadstring"),
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
  await rest.put(
    Routes.applicationCommands(config.discordClientId),
    { body: commands }
  );
  await rest.put(
    Routes.applicationGuildCommands(config.discordClientId, config.discordGuildId),
    { body: commands }
  );
  console.log("Registered slash commands globally (DM) and for guild (instant updates).");

  const client = new Client({ intents: [GatewayIntentBits.Guilds] });

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
        if (config.memberRoleId && interaction.guild) {
          const member = await interaction.guild.members.fetch(interaction.user.id);
          if (member) {
            await member.roles.add(config.memberRoleId).catch(() => null);
          }
        }
        await interaction.reply({
          content: `Registered \`${username}\`${config.memberRoleId ? " and role assigned" : ""}`,
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
        const key = await issueKey({ tier: "Member", durationDays: days });
        await interaction.reply({ content: `Issued key: \`${key.code}\``, ephemeral: true });
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
        await setBlacklist(username, true);
        await interaction.reply({ content: `Blacklisted \`${username}\``, ephemeral: true });
        return;
      }

      if (interaction.commandName === "unblacklist") {
        requireAdmin(interaction);
        const username = interaction.options.getString("user", true);
        await setBlacklist(username, false);
        await interaction.reply({ content: `Unblacklisted \`${username}\``, ephemeral: true });
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
        const keys = await issueBulk(days, count);
        await interaction.reply({
          content: `Issued ${keys.length} keys:\n${keys.slice(0, 20).map((k) => `\`${k.code}\``).join("\n")}`,
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
        const targetUser = interaction.options.getUser("user");
        const targetText = interaction.options.getString("target");
        const identity = targetUser ? targetUser.id : targetText;
        if (!identity) throw new Error("Provide either user:@discord or target:<username|discord id>");
        const out = await enqueueKickByDiscordId(identity);
        await interaction.reply({
          content: `Kick queued for **${out.username}** (next client poll, ~15s).`,
          ephemeral: true,
        });
        return;
      }

      if (interaction.commandName === "message") {
        requireAdmin(interaction);
        const targetUser = interaction.options.getUser("user");
        const targetText = interaction.options.getString("target");
        const identity = targetUser ? targetUser.id : targetText;
        if (!identity) throw new Error("Provide either user:@discord or target:<username|discord id>");
        const text = interaction.options.getString("text", true);
        const out = await enqueueMessageByDiscordId(identity, text);
        await interaction.reply({
          content: `Message queued for **${out.username}** (shows on next poll).`,
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
