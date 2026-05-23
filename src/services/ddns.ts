import { Config } from "../types/index.js";
import { resolvePublicIpv4 } from "./ipResolver.js";
import { CloudflareService } from "./cloudflare.js";
import { StateManager } from "./state.js";
import { logger } from "../utils/logger.js";

export class DDNSService {
  private readonly cf: CloudflareService;
  private readonly state: StateManager;
  private readonly config: Config;
  private timer: ReturnType<typeof setTimeout> | null = null;

  constructor(config: Config) {
    this.config = config;
    this.cf = new CloudflareService(config.cloudflareApiToken, config.zoneId);
    this.state = new StateManager();
  }

  /**
   * Run a single DDNS check cycle.
   */
  async check(): Promise<void> {
    let currentIp: string;

    try {
      currentIp = await resolvePublicIpv4();
    } catch (err) {
      logger.error(`Failed to resolve public IP: ${err instanceof Error ? err.message : err}`);
      this.state.setLastCheck();
      return;
    }

    const previousIp = this.state.trackedIp;
    this.state.setLastCheck();

    // First run: discover which records share this IP and start tracking
    if (previousIp === null) {
      logger.info(`First run — public IP is ${currentIp}. Discovering matching DNS records…`);

      const records = await this.cf.getARecordsWithIp(currentIp);
      if (records.length === 0) {
        logger.warn(
          `No A records found pointing to ${currentIp}. ` +
          `Make sure your DNS records are set to this IP before starting the updater.`
        );
      } else {
        logger.success(`Tracking ${records.length} record(s): ${records.map(r => r.name).join(", ")}`);
      }

      this.state.setTrackedIp(currentIp, records.map(r => r.name));
      return;
    }

    // Subsequent runs: compare and update if changed
    if (currentIp === previousIp) {
      logger.info(`IP unchanged: ${currentIp}`);
      return;
    }

    logger.info(`IP change detected: ${previousIp} → ${currentIp}`);

    const updated = await this.cf.updateRecordsFromIp(previousIp, currentIp);

    if (updated.length > 0) {
      logger.success(`Updated ${updated.length} DNS record(s) to ${currentIp}`);
      this.state.setTrackedIp(currentIp, updated);
    } else {
      // Records may have already been manually updated or none matched.
      // Update tracked IP anyway so we don't keep trying stale data.
      logger.warn(`No records were updated. Advancing tracked IP to ${currentIp} anyway.`);
      this.state.setTrackedIp(currentIp, []);
    }
  }

  /** Start the polling loop. */
  start(): void {
    const intervalSec = this.config.checkIntervalMs / 1000;
    logger.info(`DDNS service starting — checking every ${intervalSec}s`);
    logger.info(`Zone ID: ${this.config.zoneId}`);

    const run = async () => {
      try {
        await this.check();
      } catch (err) {
        logger.error(`Unexpected error during check cycle: ${err}`);
      } finally {
        this.timer = setTimeout(run, this.config.checkIntervalMs);
      }
    };

    // Run immediately, then on interval
    run();
  }

  /** Gracefully stop the service. */
  stop(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    logger.info("DDNS service stopped.");
  }
}
