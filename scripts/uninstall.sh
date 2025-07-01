#!/bin/bash
set -e

# === Colors ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SERVICE_NAME="postgresql-fyi"
SERVICE_USER="postgresql-fyi"
SERVICE_GROUP="postgresql-fyi"
INSTALL_DIR="/opt/postgresql-fyi"
LOG_DIR="/var/log/postgresql-fyi"
CONFIG_DIR="/etc/postgresql-fyi"

echo -e "${BLUE}🧹 Complete Uninstallation of ${SERVICE_NAME}...${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ This script must be run as root (use sudo)${NC}"
   exit 1
fi

# Stop the service
echo -e "${YELLOW}⛔ Stopping service...${NC}"
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME"
    echo -e "${GREEN}✅ Service stopped.${NC}"
else
    echo -e "${YELLOW}ℹ️  Service was not running.${NC}"
fi

# Disable the service
echo -e "${YELLOW}🔌 Disabling service...${NC}"
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME"
    echo -e "${GREEN}✅ Service disabled.${NC}"
else
    echo -e "${YELLOW}ℹ️  Service was not enabled.${NC}"
fi

# Remove service file
echo -e "${YELLOW}🗑️  Removing systemd service file...${NC}"
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    rm "/etc/systemd/system/${SERVICE_NAME}.service"
    echo -e "${GREEN}✅ Systemd service file removed.${NC}"
else
    echo -e "${YELLOW}ℹ️  Systemd service file not found.${NC}"
fi

# Reload systemd and reset failed units
echo -e "${YELLOW}🔄 Reloading systemd...${NC}"
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# Remove directories
echo -e "${YELLOW}📁 Removing directories...${NC}"
for dir in "$INSTALL_DIR" "$LOG_DIR" "$CONFIG_DIR"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        echo -e "${GREEN}✅ Removed: $dir${NC}"
    else
        echo -e "${YELLOW}ℹ️  Directory not found: $dir${NC}"
    fi
done

# Remove log rotation config
echo -e "${YELLOW}📋 Removing log rotation config...${NC}"
if [ -f "/etc/logrotate.d/$SERVICE_NAME" ]; then
    rm "/etc/logrotate.d/$SERVICE_NAME"
    echo -e "${GREEN}✅ Log rotation config removed.${NC}"
else
    echo -e "${YELLOW}ℹ️  Log rotation config not found.${NC}"
fi

# Remove management script
echo -e "${YELLOW}📜 Removing management script...${NC}"
if [ -f "/usr/local/bin/$SERVICE_NAME" ]; then
    rm "/usr/local/bin/$SERVICE_NAME"
    echo -e "${GREEN}✅ Management script removed.${NC}"
else
    echo -e "${YELLOW}ℹ️  Management script not found.${NC}"
fi

# Remove service user
echo -e "${YELLOW}👤 Removing service user...${NC}"
if getent passwd "$SERVICE_USER" >/dev/null 2>&1; then
    userdel "$SERVICE_USER"
    echo -e "${GREEN}✅ User removed: $SERVICE_USER${NC}"
else
    echo -e "${YELLOW}ℹ️  User not found: $SERVICE_USER${NC}"
fi

# Remove service group
echo -e "${YELLOW}👥 Removing service group...${NC}"
if getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
    groupdel "$SERVICE_GROUP"
    echo -e "${GREEN}✅ Group removed: $SERVICE_GROUP${NC}"
else
    echo -e "${YELLOW}ℹ️  Group not found: $SERVICE_GROUP${NC}"
fi

# Final systemd cleanup
echo -e "${YELLOW}🧽 Final systemd cleanup...${NC}"
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo -e "${GREEN}✅ Complete uninstallation finished!${NC}"
echo ""
echo -e "${BLUE}🔍 Verification:${NC}"
echo "Run these commands to verify complete removal:"
echo "  systemctl status $SERVICE_NAME  # Should show 'not found'"
echo "  getent passwd $SERVICE_USER     # Should return nothing"
echo "  ls -la $INSTALL_DIR             # Should show 'No such file'"
echo ""
echo -e "${GREEN}🎉 Ready for fresh installation!${NC}"