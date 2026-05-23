#!/usr/bin/env bash
# =============================================================================
#  Cloudflare DDNS Installer
#  Usage (curl):  bash <(curl -fsSL https://raw.githubusercontent.com/lennoxrose/cloudflare-ddns/main/install.sh)
#  Usage (local): ./install.sh
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';     RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
section() { echo -e "\n${BOLD}━━━  $*  ━━━${RESET}"; }

# Config
REPO_URL="https://github.com/lennoxrose/cloudflare-ddns"
INSTALL_DIR="/opt/cloudflare-ddns"
SERVICE_NAME="cloudflare-ddns"
ENV_FILE="/etc/cloudflare-ddns/env"
DDNS_USER="cloudflare-ddns"

# Detect if we're already running inside the repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/package.json" ]] && grep -q '"name": "cloudflare-ddns"' "$SCRIPT_DIR/package.json" 2>/dev/null; then
  SOURCE_DIR="$SCRIPT_DIR"
  MODE="local"
else
  SOURCE_DIR=""
  MODE="remote"
fi

# Banner
echo -e "
${CYAN}╔══════════════════════════════════════╗
║      Cloudflare DDNS Installer       ║
║   IPv4 auto-sync for your zone       ║
╚══════════════════════════════════════╝${RESET}
Mode     : ${BOLD}${MODE}${RESET}
Install  : ${BOLD}${INSTALL_DIR}${RESET}
"

# Root check
[[ $EUID -eq 0 ]] || die "Please run as root:  sudo bash install.sh"

# OS detection
section "Detecting system"

OS=""
PKG_MANAGER=""

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  OS="${ID:-unknown}"
fi

case "$OS" in
  ubuntu|debian|raspbian)  PKG_MANAGER="apt"  ;;
  fedora)                  PKG_MANAGER="dnf"  ;;
  centos|rhel|rocky|almalinux) PKG_MANAGER="dnf" ;;
  arch|manjaro)            PKG_MANAGER="pacman" ;;
  opensuse*|sles)          PKG_MANAGER="zypper" ;;
  *) warn "Unknown OS '${OS}'. Will attempt apt-based install." ; PKG_MANAGER="apt" ;;
esac

info "OS: ${OS}  |  Package manager: ${PKG_MANAGER}"

# Helper: command exists
has() { command -v "$1" &>/dev/null; }

# Ask for deployment mode
section "Deployment mode"

echo -e "How would you like to run Cloudflare DDNS?\n"
echo "  1) Docker  (recommended — isolated, easy updates)"
echo "  2) systemd (native Node.js service, no Docker)"
echo ""
read -rp "Choice [1/2]: " DEPLOY_MODE
DEPLOY_MODE="${DEPLOY_MODE:-1}"

[[ "$DEPLOY_MODE" == "1" || "$DEPLOY_MODE" == "2" ]] \
  || die "Invalid choice. Run the script again and enter 1 or 2."

# Install base packages
section "Installing base dependencies"

install_pkgs() {
  case "$PKG_MANAGER" in
    apt)    apt-get update -qq && apt-get install -y -qq "$@" ;;
    dnf)    dnf install -y -q "$@" ;;
    pacman) pacman -Sy --noconfirm "$@" ;;
    zypper) zypper install -y "$@" ;;
  esac
}

BASE_DEPS=(curl git)
info "Installing: ${BASE_DEPS[*]}"
install_pkgs "${BASE_DEPS[@]}"
success "Base deps ready"

# Install Docker (mode 1)
install_docker() {
  if has docker; then
    success "Docker already installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
    return
  fi

  info "Installing Docker…"

  case "$PKG_MANAGER" in
    apt)
      install_pkgs ca-certificates gnupg lsb-release
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/${OS}/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/${OS} $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update -qq
      install_pkgs docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    dnf)
      dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || true
      install_pkgs docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    pacman)
      install_pkgs docker docker-compose
      ;;
    *)
      # Universal fallback
      curl -fsSL https://get.docker.com | sh
      ;;
  esac

  systemctl enable --now docker
  success "Docker installed and started"
}

# Install Node.js (mode 2)
install_node() {
  if has node; then
    NODE_VER=$(node --version)
    MAJOR="${NODE_VER//[^0-9.]*/}"
    MAJOR="${MAJOR%%.*}"
    MAJOR="${MAJOR#v}"
    if [[ "${MAJOR:-0}" -ge 20 ]]; then
      success "Node.js already installed ($NODE_VER)"
      return
    fi
    warn "Node.js $NODE_VER is too old (need ≥20). Upgrading…"
  else
    info "Installing Node.js 22 LTS…"
  fi

  case "$PKG_MANAGER" in
    apt)
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
      install_pkgs nodejs
      ;;
    dnf)
      curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
      install_pkgs nodejs
      ;;
    pacman)
      install_pkgs nodejs npm
      ;;
    *)
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
      install_pkgs nodejs
      ;;
  esac

  success "Node.js installed ($(node --version))"
}

# Get the source code
section "Setting up source"

if [[ "$MODE" == "local" ]]; then
  info "Source detected at: $SOURCE_DIR"
  if [[ "$SOURCE_DIR" != "$INSTALL_DIR" ]]; then
    info "Copying to $INSTALL_DIR…"
    mkdir -p "$INSTALL_DIR"
    # Copy everything except node_modules and dist
    rsync -a --exclude='node_modules/' --exclude='dist/' \
      "$SOURCE_DIR/" "$INSTALL_DIR/" 2>/dev/null \
      || { cp -r "$SOURCE_DIR/." "$INSTALL_DIR/"; rm -rf "$INSTALL_DIR/node_modules" "$INSTALL_DIR/dist"; }
  fi
  success "Source ready at $INSTALL_DIR"
else
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Repo already cloned — pulling latest…"
    git -C "$INSTALL_DIR" pull --ff-only
  else
    info "Cloning $REPO_URL → $INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
  success "Source cloned"
fi

# Collect credentials
section "Cloudflare credentials"

echo ""
echo "You need a Cloudflare API token with DNS:Edit for your zone."
echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
echo "Use the 'Edit zone DNS' template, scoped to your zone."
echo ""

read -rp "  CF_API_TOKEN          : " CF_API_TOKEN
[[ -n "$CF_API_TOKEN" ]] || die "API token cannot be empty."

read -rp "  CF_ZONE_ID            : " CF_ZONE_ID
[[ -n "$CF_ZONE_ID" ]] || die "Zone ID cannot be empty."

read -rp "  CHECK_INTERVAL_SECONDS [300]: " CHECK_INTERVAL
CHECK_INTERVAL="${CHECK_INTERVAL:-300}"

# Docker install
if [[ "$DEPLOY_MODE" == "1" ]]; then

  install_docker

  section "Configuring Docker deployment"

  ENV_TARGET="$INSTALL_DIR/.env"
  cat > "$ENV_TARGET" <<EOF
CF_API_TOKEN=${CF_API_TOKEN}
CF_ZONE_ID=${CF_ZONE_ID}
CHECK_INTERVAL_SECONDS=${CHECK_INTERVAL}
EOF
  chmod 600 "$ENV_TARGET"
  success "Wrote $ENV_TARGET"

  section "Building and starting container"
  cd "$INSTALL_DIR"
  docker compose up -d --build
  success "Container started"

  section "Installing systemd service"
  DOCKER_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
  DOCKER_BIN=$(command -v docker)

  cat > "$DOCKER_SERVICE_FILE" <<EOF
[Unit]
Description=Cloudflare DDNS (Docker)
Documentation=${REPO_URL}
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
WorkingDirectory=${INSTALL_DIR}
ExecStart=${DOCKER_BIN} compose up
ExecStop=${DOCKER_BIN} compose down
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  success "Service enabled and started"

  echo ""
  info "View logs:    journalctl -u ${SERVICE_NAME} -f"
  info "Status:       systemctl status ${SERVICE_NAME}"
  info "Stop:         systemctl stop ${SERVICE_NAME}"
  info "Restart:      systemctl restart ${SERVICE_NAME}"
  info "Docker logs:  docker compose -f $INSTALL_DIR/docker-compose.yml logs -f"

# systemd install
else

  install_node

  section "Building TypeScript"
  cd "$INSTALL_DIR"
  npm ci --prefer-offline 2>/dev/null || npm install
  npm run build
  success "Build complete"

  section "Creating system user"
  if id "$DDNS_USER" &>/dev/null; then
    success "User '$DDNS_USER' already exists"
  else
    useradd --system --no-create-home --shell /usr/sbin/nologin "$DDNS_USER"
    success "Created user '$DDNS_USER'"
  fi

  section "Writing env file"
  mkdir -p "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" <<EOF
CF_API_TOKEN=${CF_API_TOKEN}
CF_ZONE_ID=${CF_ZONE_ID}
CHECK_INTERVAL_SECONDS=${CHECK_INTERVAL}
STATE_FILE_PATH=/var/lib/cloudflare-ddns/ddns-state.json
EOF
  chmod 600 "$ENV_FILE"
  chown root:"$DDNS_USER" "$ENV_FILE"
  success "Wrote $ENV_FILE"

  section "Installing systemd service"
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Cloudflare DDNS Updater
Documentation=${REPO_URL}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=on-failure
RestartSec=10s
User=${DDNS_USER}
Group=${DDNS_USER}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/node ${INSTALL_DIR}/dist/index.js
StateDirectory=${SERVICE_NAME}
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

  chown root:root "$INSTALL_DIR" -R
  chmod 755 "$INSTALL_DIR"

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  success "Service enabled and started"

  echo ""
  info "View logs:  journalctl -u ${SERVICE_NAME} -f"
  info "Status:     systemctl status ${SERVICE_NAME}"
  info "Restart:    systemctl restart ${SERVICE_NAME}"
  info "Stop:       systemctl stop ${SERVICE_NAME}"

fi

# Done
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════╗
║   Cloudflare DDNS is now running!    ║
╚══════════════════════════════════════╝${RESET}"
echo ""