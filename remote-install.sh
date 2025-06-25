#!/bin/bash

set -euo pipefail

# === Config ===
DEBUG_MODE=false
START_SERVICE=true
TEMP_DIR=$(mktemp -d)
REPO_URL="https://github.com/AkbarHabeeb/postgresql-fyi-e2e"
ARCHIVE_URL="$REPO_URL/archive/refs/heads/main.tar.gz"

# === Colors ===
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

# === Cleanup ===
cleanup() {
    if [ "$DEBUG_MODE" = false ]; then
        rm -rf "$TEMP_DIR"
    else
        echo -e "${YELLOW}⚠️  Debug mode enabled. Temp dir preserved: $TEMP_DIR${NC}"
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
        *) echo -e "${RED}Unknown option: $arg${NC}"; exit 1 ;;
    esac
done

# === Pre-checks ===
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}❌ Do not run as root. Use a regular user with sudo privileges.${NC}"
   exit 1
fi

if ! command -v systemctl >/dev/null; then
    echo -e "${RED}❌ systemd is required (Ubuntu 16+, etc).${NC}"
    exit 1
fi

if ! command -v curl >/dev/null; then
    echo -e "${YELLOW}⚠️  Installing curl...${NC}"
    sudo apt-get update && sudo apt-get install -y curl
fi

if ! command -v tar >/dev/null; then
    echo -e "${YELLOW}⚠️  Installing tar...${NC}"
    sudo apt-get update && sudo apt-get install -y tar
fi

# === Begin Install ===
echo -e "${BLUE}🐘 Installing PostgreSQL FYI Service...${NC}"

cd "$TEMP_DIR"
echo -e "${YELLOW}📥 Downloading package...${NC}"
curl -L "$ARCHIVE_URL" -o app.tar.gz

echo -e "${YELLOW}📦 Extracting package...${NC}"
tar -xzf app.tar.gz
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "postgresql-fyi-e2e-*")
cd "$EXTRACTED_DIR"

echo -e "${YELLOW}📁 Working in directory: $EXTRACTED_DIR${NC}"

chmod +x scripts/*.sh

echo -e "${YELLOW}🔧 Running install script...${NC}"
sudo ./scripts/install.sh

if [ "$START_SERVICE" = true ]; then
    echo -e "${YELLOW}🚀 Starting service...${NC}"
    sudo systemctl enable postgresql-fyi
    sudo systemctl start postgresql-fyi
    sleep 2

    if curl -s http://localhost:1234/health >/dev/null; then
        echo -e "${GREEN}✅ Service is up and running!${NC}"
    else
        echo -e "${YELLOW}⚠️  Service installed but not reachable on /health.${NC}"
    fi
else
    echo -e "${YELLOW}⏭️  Skipping service start (--no-start used).${NC}"
fi

echo -e "${GREEN}🎉 PostgreSQL FYI Service is ready!${NC}"
echo -e "${BLUE}📋 Manage via: sudo systemctl <start|stop|restart|status> postgresql-fyi${NC}"
