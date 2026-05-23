export interface Config {
  cloudflareApiToken: string;
  zoneId: string;
  checkIntervalMs: number;
}

export interface DnsRecord {
  id: string;
  name: string;
  type: string;
  content: string;
  proxied: boolean;
  ttl: number;
  comment?: string;
}

export interface DDNSState {
  trackedIp: string | null;
  lastCheck: Date | null;
  lastUpdate: Date | null;
  updatedRecords: string[];
}
