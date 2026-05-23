import Cloudflare from "cloudflare";
import { DnsRecord } from "../types/index.js";
import { logger } from "../utils/logger.js";

export class CloudflareService {
  private readonly client: Cloudflare;
  private readonly zoneId: string;

  constructor(apiToken: string, zoneId: string) {
    this.client = new Cloudflare({ apiToken });
    this.zoneId = zoneId;
  }

  /**
   * Fetch all A records in the zone that match the given IP address.
   * Uses the SDK's async iterator for automatic pagination.
   */
  async getARecordsWithIp(ip: string): Promise<DnsRecord[]> {
    logger.debug(`Fetching A records matching IP ${ip}…`);

    const matching: DnsRecord[] = [];

    // The SDK returns an async iterable page — iterate it directly
    for await (const record of await this.client.dns.records.list({
      zone_id: this.zoneId,
      type: "A",
      // content filter uses the Content object shape
      content: { exact: ip },
      per_page: 100,
    })) {
      if (record.id && record.name && record.content && record.type === "A") {
        matching.push({
          id: record.id,
          name: record.name,
          type: record.type,
          content: record.content,
          proxied: record.proxied ?? false,
          ttl: record.ttl ?? 1,
          comment: record.comment ?? undefined,
        });
      }
    }

    logger.debug(`Found ${matching.length} A record(s) matching ${ip}`);
    return matching;
  }

  /**
   * Update a single A record to a new IP.
   */
  async updateRecord(record: DnsRecord, newIp: string): Promise<void> {
    logger.debug(`Updating record ${record.name} (${record.id}) → ${newIp}`);

    await this.client.dns.records.update(record.id, {
      zone_id: this.zoneId,
      type: "A",
      name: record.name,
      content: newIp,
      proxied: record.proxied,
      // TTL: 1 = automatic; otherwise must be 30–86400
      ttl: (record.ttl === 1 || (record.ttl >= 30 && record.ttl <= 86400))
        ? record.ttl as 1 | number
        : 1,
      ...(record.comment !== undefined && { comment: record.comment }),
    });
  }

  /**
   * Update all A records that currently point to oldIp → newIp.
   * Returns the list of record names that were updated.
   */
  async updateRecordsFromIp(oldIp: string, newIp: string): Promise<string[]> {
    const records = await this.getARecordsWithIp(oldIp);

    if (records.length === 0) {
      logger.warn(`No A records found pointing to ${oldIp}. Nothing to update.`);
      return [];
    }

    logger.info(`Updating ${records.length} record(s): ${oldIp} → ${newIp}`);

    const updated: string[] = [];
    const failed: string[] = [];

    for (const record of records) {
      try {
        await this.updateRecord(record, newIp);
        updated.push(record.name);
        logger.success(`  ✓ ${record.name}`);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.error(`  ✗ ${record.name}: ${msg}`);
        failed.push(record.name);
      }
    }

    if (failed.length > 0) {
      logger.warn(`${failed.length} record(s) failed to update: ${failed.join(", ")}`);
    }

    return updated;
  }
}
