# Cloudflare DDNS

[![TypeScript](https://img.shields.io/badge/TypeScript-5.x-3178C6?logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-DNS-F38020?logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)

Automatically keeps your Cloudflare DNS A records in sync with your public IPv4 address. On first run it discovers every A record in your zone that matches your current IP and tracks them — when your IP changes, all of them are updated in one pass.

## Requirements

- A Cloudflare API token with **DNS:Edit** permission scoped to your zone
- Your **Zone ID** (found on the zone Overview page in the Cloudflare dashboard)
- Docker **or** Node.js ≥ 20

## Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lennoxrose/cloudflare-ddns/main/install.sh)
```

The installer will ask whether to run via **Docker** (recommended) or a native **systemd** service, then collect your credentials and handle everything else.

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `CF_API_TOKEN` | Yes | — | Cloudflare API token (DNS:Edit) |
| `CF_ZONE_ID` | Yes | — | Cloudflare Zone ID |
| `CHECK_INTERVAL_SECONDS` | No | `300` | How often to check for an IP change |
| `STATE_FILE_PATH` | No | `/data/ddns-state.json` | Where to persist tracked-IP state |

**Docker:** credentials live in `/opt/cloudflare-ddns/.env` (mode 600).  
**systemd:** credentials live in `/etc/cloudflare-ddns/env` (mode 600, owned by root:cloudflare-ddns).

## Usage

### Docker (managed by systemd)

```bash
systemctl status cloudflare-ddns      # service status
journalctl -u cloudflare-ddns -f      # live logs
systemctl restart cloudflare-ddns     # restart
systemctl stop cloudflare-ddns        # stop
```

### systemd (native Node.js)

```bash
systemctl status cloudflare-ddns
journalctl -u cloudflare-ddns -f
systemctl restart cloudflare-ddns
```

## How it works

1. Resolves your current public IPv4 via `api4.my-ip.io`
2. On first run, fetches all A records in your zone that match that IP and saves them as the tracked set
3. On every subsequent check, if the IP has changed it updates every tracked record via the Cloudflare API and persists the new state
4. State is written to a JSON file so the tracked record list survives restarts
