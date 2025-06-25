#!/bin/bash

set -euo pipefail

# === Constants ===
INSTALL_LOG="/var/log/postgresql-fyi-install.log"
DEBUG_MODE=false
START_SERVICE=true
TEMP_DIR=$(mktemp -d)
REPO_URL="https://github.com/AkbarHabeeb/postgresql-fyi-e2e"
ARCHIVE_URL="$REPO_URL/archive/refs/heads/main.tar.gz"

# === Colors ===
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

# === Logging ===
log() { echo -e "$1" | tee -a "$INSTALL_LOG"; }

# === Cleanup ===
cleanup() {
    if [ "$DEBUG_MODE" = false ]; then
        rm -rf "$TEMP_DIR"
    else
        log "${YELLOW}⚠️  Debug mode enabled. Temp dir preserved: $TEMP_DIR${NC}"
    fi
}
trap cleanup EXIT

# === Help ===
print_help() {
    cat <<EOF
Usage: install.sh [options]

Options:
  --debug        Keep temp files after installation
  --no-start     Don't start the service after install
  --help         Show this help message
EOF
    exit 0
}

# === Parse Args ===
for arg in "$@"; do
    case $arg in
        --debug) DEBUG_MODE=true ;;
        --no-start) START_SERVICE=false ;;
        --help) print_help ;;
        *) log "${RED}Unknown option: $arg${NC}"; exit 1 ;;
    esac
done

# === Pre-checks ===
if [[ $EUID -eq 0 ]]; then
   log "${RED}❌ Do not run as root. Use a regular user with sudo privileges.${NC}"
   exit 1
fi

if ! command -v systemctl >/dev/null; then
    log "${RED}❌ systemd is required (Ubuntu 16+, etc).${NC}"
    exit 1
fi

if ! command -v curl >/dev/null; then
    log "${YELLOW}⚠️  Installing curl...${NC}"
    sudo apt-get update && sudo apt-get install -y curl
fi

if ! command -v tar >/dev/null; then
    log "${YELLOW}⚠️  Installing tar...${NC}"
    sudo apt-get update && sudo apt-get install -y tar
fi

# === Begin Install ===
log "${BLUE}🐘 Installing PostgreSQL FYI Service...${NC}"
log "Logs will be written to $INSTALL_LOG"

cd "$TEMP_DIR"
log "${YELLOW}📥 Downloading package...${NC}"
curl -L "$ARCHIVE_URL" -o app.tar.gz

log "${YELLOW}📦 Extracting package...${NC}"
tar -xzf app.tar.gz
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "postgresql-fyi-e2e-*")
cd "$EXTRACTED_DIR"

if [[ -f VERSION ]]; then
    VERSION=$(cat VERSION)
    log "${GREEN}📌 Version: $VERSION${NC}"
else
    log "${YELLOW}⚠️  VERSION file missing.${NC}"
fi

chmod +x scripts/*.sh

log "${YELLOW}🔧 Running install script...${NC}"
sudo ./scripts/install.sh

if [ "$START_SERVICE" = true ]; then
    log "${YELLOW}🚀 Starting service...${NC}"
    sudo systemctl enable postgresql-fyi
    sudo systemctl start postgresql-fyi
    sleep 2

    if curl -s http://localhost:1234/health >/dev/null; then
        log "${GREEN}✅ Service is up and running!${NC}"
    else
        log "${YELLOW}⚠️  Service installed but not reachable on /health.${NC}"
    fi
else
    log "${YELLOW}⏭️  Skipping service start (--no-start used).${NC}"
fi

log "${GREEN}🎉 Done! You can now use the PostgreSQL FYI Service.${NC}"
log "${BLUE}📋 Manage via: sudo systemctl <start|stop|restart|status> postgresql-fyi${NC}"
