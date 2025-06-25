#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🐘 PostgreSQL FYI Service - One-Line Installer${NC}"
echo "=============================================="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}❌ Don't run this script as root. It will use sudo when needed.${NC}"
   exit 1
fi

# Check OS
if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}❌ This installer requires systemd (Ubuntu 16+, Debian 8+, CentOS 7+)${NC}"
    exit 1
fi

echo -e "${YELLOW}📥 Downloading PostgreSQL FYI Service from GitHub...${NC}"

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

GITHUB_URL="https://github.com/AkbarHabeeb/postgresql-fyi-e2e/archive/refs/heads/main.tar.gz"
if ! curl -L -o postgresql-fyi.tar.gz "$GITHUB_URL"; then
    echo -e "${RED}❌ Failed to download package. Check your internet connection.${NC}"
    exit 1
fi

echo -e "${YELLOW}📦 Extracting package...${NC}"

tar -xzf postgresql-fyi.tar.gz
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "postgresql-fyi-e2e-*")
cd "$EXTRACTED_DIR"
echo -e "${YELLOW}📁 Working in directory: $EXTRACTED_DIR${NC}"

# Make scripts executable
chmod +x scripts/*.sh

echo -e "${YELLOW}🔧 Installing PostgreSQL FYI Service...${NC}"

# Run the existing installation script
sudo ./scripts/install.sh

echo -e "${YELLOW}🚀 Starting service...${NC}"

# Start and enable service
sudo systemctl start postgresql-fyi
sudo systemctl enable postgresql-fyi

# Wait for service to start
sleep 3

echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo -e "${GREEN}🌐 Service running on: http://localhost:1234${NC}"
echo ""

# Test health check
echo -e "${YELLOW}🔍 Testing service...${NC}"
if curl -s http://localhost:1234/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Service is healthy and ready to use!${NC}"
    echo ""
    echo -e "${BLUE}📋 Quick test:${NC}"
    echo "curl http://localhost:1234/health"
else
    echo -e "${YELLOW}⚠️  Service installed but may still be starting...${NC}"
    echo "Check status: systemctl status postgresql-fyi"
fi

echo ""
echo -e "${BLUE}📚 Management Commands:${NC}"
echo "  Start:    sudo systemctl start postgresql-fyi"
echo "  Stop:     sudo systemctl stop postgresql-fyi"  
echo "  Restart:  sudo systemctl restart postgresql-fyi"
echo "  Status:   systemctl status postgresql-fyi"
echo "  Logs:     journalctl -u postgresql-fyi -f"
echo "  Health:   curl http://localhost:1234/health"

# Cleanup
cd /
rm -rf $TEMP_DIR

echo ""
echo -e "${GREEN}🎉 PostgreSQL FYI Service is ready!${NC}"
echo -e "${BLUE}Start using at: https://postgresql.fyi${NC}"
