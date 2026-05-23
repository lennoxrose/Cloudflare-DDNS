import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { dirname } from "path";
import { DDNSState } from "../types/index.js";
import { logger } from "../utils/logger.js";

export class StateManager {
  private readonly filePath: string;
  private state: DDNSState;

  constructor(filePath: string = "/data/ddns-state.json") {
    this.filePath = filePath;
    this.state = this.load();
  }

  private load(): DDNSState {
    try {
      if (existsSync(this.filePath)) {
        const raw = readFileSync(this.filePath, "utf-8");
        const parsed = JSON.parse(raw);
        logger.info(`Loaded persisted state — tracked IP: ${parsed.trackedIp ?? "none"}`);
        return {
          trackedIp: parsed.trackedIp ?? null,
          lastCheck: parsed.lastCheck ? new Date(parsed.lastCheck) : null,
          lastUpdate: parsed.lastUpdate ? new Date(parsed.lastUpdate) : null,
          updatedRecords: parsed.updatedRecords ?? [],
        };
      }
    } catch (err) {
      logger.warn(`Could not load state file, starting fresh: ${err}`);
    }
    return { trackedIp: null, lastCheck: null, lastUpdate: null, updatedRecords: [] };
  }

  private save(): void {
    try {
      const dir = dirname(this.filePath);
      if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
      writeFileSync(this.filePath, JSON.stringify(this.state, null, 2), "utf-8");
    } catch (err) {
      logger.warn(`Could not persist state: ${err}`);
    }
  }

  get trackedIp(): string | null {
    return this.state.trackedIp;
  }

  setTrackedIp(ip: string, updatedRecords: string[] = []): void {
    this.state.trackedIp = ip;
    this.state.lastUpdate = new Date();
    this.state.updatedRecords = updatedRecords;
    this.save();
  }

  setLastCheck(date: Date = new Date()): void {
    this.state.lastCheck = date;
    this.save();
  }

  getState(): Readonly<DDNSState> {
    return { ...this.state };
  }
}
