import { config } from "./config.js";
import { prisma } from "./db.js";
import { createApi } from "./api.js";
import { startBot } from "./bot.js";

async function main() {
  await prisma.$connect();
  const app = createApi();
  app.listen(config.apiPort, () => {
    console.log(`Auth API listening on :${config.apiPort}`);
  });
  await startBot();
}

main().catch(async (err) => {
  console.error(err);
  await prisma.$disconnect();
  process.exit(1);
});
