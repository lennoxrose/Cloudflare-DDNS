type LogLevel = "INFO" | "WARN" | "ERROR" | "SUCCESS" | "DEBUG";

const COLORS: Record<LogLevel, string> = {
  INFO:    "\x1b[36m",  // cyan
  WARN:    "\x1b[33m",  // yellow
  ERROR:   "\x1b[31m",  // red
  SUCCESS: "\x1b[32m",  // green
  DEBUG:   "\x1b[90m",  // gray
};
const RESET = "\x1b[0m";

function timestamp(): string {
  return new Date().toISOString();
}

function log(level: LogLevel, message: string, ...args: unknown[]): void {
  const color = COLORS[level];
  const prefix = `${color}[${level.padEnd(7)}]${RESET} ${timestamp()} —`;
  const extra = args.length ? " " + args.map(a => JSON.stringify(a)).join(" ") : "";
  console.log(`${prefix} ${message}${extra}`);
}

export const logger = {
  info:    (msg: string, ...args: unknown[]) => log("INFO",    msg, ...args),
  warn:    (msg: string, ...args: unknown[]) => log("WARN",    msg, ...args),
  error:   (msg: string, ...args: unknown[]) => log("ERROR",   msg, ...args),
  success: (msg: string, ...args: unknown[]) => log("SUCCESS", msg, ...args),
  debug:   (msg: string, ...args: unknown[]) => log("DEBUG",   msg, ...args),
};
