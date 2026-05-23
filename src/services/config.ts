import { Config } from "../types/index.js";
import { logger } from "../utils/logger.js";

const DEFAULT_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes

export function loadConfig(): Config {
  const token = process.env.CF_API_TOKEN;
  const zoneId = process.env.CF_ZONE_ID;
  const intervalRaw = process.env.CHECK_INTERVAL_SECONDS;

  const missing: string[] = [];
  if (!token)  missing.push("CF_API_TOKEN");
  if (!zoneId) missing.push("CF_ZONE_ID");

  if (missing.length > 0) {
    logger.error(`Missing required environment variables: ${missing.join(", ")}`);
    logger.error("See the README for setup instructions.");
    process.exit(1);
  }

  let checkIntervalMs = DEFAULT_INTERVAL_MS;
  if (intervalRaw) {
    const seconds = parseInt(intervalRaw, 10);
    if (isNaN(seconds) || seconds < 30) {
      logger.warn(`CHECK_INTERVAL_SECONDS="${intervalRaw}" is invalid or too low (min 30s). Using default 300s.`);
    } else {
      checkIntervalMs = seconds * 1000;
    }
  }

  return {
    cloudflareApiToken: token!,
    zoneId: zoneId!,
    checkIntervalMs,
  };
}
