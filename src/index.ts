import { loadConfig } from "./services/config.js";
import { DDNSService } from "./services/ddns.js";
import { logger } from "./utils/logger.js";

function printBanner(): void {
  console.log(`
\x1b[36m╔══════════════════════════════════════╗
║      Cloudflare DDNS Updater         ║
║   IPv4 → DNS  |  auto-sync every Δt  ║
╚══════════════════════════════════════╝\x1b[0m
`);
}

async function main(): Promise<void> {
  printBanner();

  const config = loadConfig();
  const service = new DDNSService(config);

  // Graceful shutdown
  const shutdown = (signal: string) => {
    logger.warn(`Received ${signal} — shutting down…`);
    service.stop();
    process.exit(0);
  };

  process.on("SIGINT",  () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));

  process.on("uncaughtException", (err) => {
    logger.error(`Uncaught exception: ${err.message}`);
    logger.error(err.stack ?? "");
    process.exit(1);
  });

  process.on("unhandledRejection", (reason) => {
    logger.error(`Unhandled rejection: ${reason}`);
    process.exit(1);
  });

  service.start();
}

main();
