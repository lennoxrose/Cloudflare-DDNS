import { logger } from "../utils/logger.js";

// Multiple providers tried in order for resilience
const IP_PROVIDERS = [
  "https://api4.my-ip.io/ip.txt",
  "https://api.ipify.org",
  "https://ipv4.icanhazip.com",
  "https://checkip.amazonaws.com",
];

const IPV4_REGEX = /^(\d{1,3}\.){3}\d{1,3}$/;

function isValidIpv4(ip: string): boolean {
  if (!IPV4_REGEX.test(ip)) return false;
  return ip.split(".").every(octet => parseInt(octet, 10) <= 255);
}

export async function resolvePublicIpv4(): Promise<string> {
  const errors: string[] = [];

  for (const url of IP_PROVIDERS) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(5000),
        headers: { "User-Agent": "cloudflare-ddns/1.0" },
      });

      if (!response.ok) {
        errors.push(`${url}: HTTP ${response.status}`);
        continue;
      }

      const ip = (await response.text()).trim();

      if (isValidIpv4(ip)) {
        logger.debug(`Resolved public IP via ${url}: ${ip}`);
        return ip;
      }

      errors.push(`${url}: invalid IPv4 "${ip}"`);
    } catch (err) {
      errors.push(`${url}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  throw new Error(`All IP providers failed:\n  ${errors.join("\n  ")}`);
}
