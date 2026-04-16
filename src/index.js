import { config } from "./config.js";
import { prisma } from "./db.js";
import { createApi } from "./api.js";
import { startBot } from "./bot.js";
import { setLogClient } from "./discordLogs.js";

async function main() {
  await prisma.$connect();
  const app = createApi();
  app.listen(config.apiPort, () => {
    console.log(`Auth API listening on :${config.apiPort}`);
  });
  const botClient = await startBot();
  setLogClient(botClient);
}

main().catch(async (err) => {
  console.error(err);
  await prisma.$disconnect();
  process.exit(1);
});
