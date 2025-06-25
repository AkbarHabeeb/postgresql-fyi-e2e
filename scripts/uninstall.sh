#!/bin/bash
set -e

# === Colors ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SERVICE_NAME="postgresql-fyi"
INSTALL_DIR="/opt/postgresql-fyi"  # Change this if you installed somewhere else

echo -e "${YELLOW}🧹 Uninstalling ${SERVICE_NAME}...${NC}"

# Stop the service
if systemctl is-active --quiet "$SERVICE_NAME"; then
    sudo systemctl stop "$SERVICE_NAME"
    echo -e "${YELLOW}⛔ Stopped service.${NC}"
fi

# Disable the service
if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    sudo systemctl disable "$SERVICE_NAME"
    echo -e "${YELLOW}🔌 Disabled service.${NC}"
fi

# Remove service file
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    sudo rm "/etc/systemd/system/${SERVICE_NAME}.service"
    echo -e "${YELLOW}🗑️  Removed systemd service file.${NC}"
fi

# Reload systemd
sudo systemctl daemon-reload

# Delete app files (if installed to a known path)
if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf "$INSTALL_DIR"
    echo -e "${YELLOW}📁 Removed install directory: $INSTALL_DIR${NC}"
fi

echo -e "${GREEN}✅ Uninstallation complete.${NC}"
