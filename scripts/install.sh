#!/bin/bash

# PostgreSQL FYI Service Installation Script
# Usage: sudo ./scripts/install.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="postgresql-fyi"
SERVICE_USER="postgresql-fyi"
SERVICE_GROUP="postgresql-fyi"
INSTALL_DIR="/opt/postgresql-fyi"
LOG_DIR="/var/log/postgresql-fyi"
CONFIG_DIR="/etc/postgresql-fyi"

echo -e "${BLUE}🐘 PostgreSQL FYI Service Installation${NC}"
echo "======================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ This script must be run as root (use sudo)${NC}"
   exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is not installed. Please install Node.js (version 16 or later) first.${NC}"
    echo "On Ubuntu/Debian: sudo apt update && sudo apt install nodejs npm"
    echo "On CentOS/RHEL: sudo yum install nodejs npm"
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node -v | sed 's/v//')
REQUIRED_VERSION="10.0.0"

# Compare using sort -V (version sort)
if ! printf "%s\n%s" "$REQUIRED_VERSION" "$NODE_VERSION" | sort -VC; then
    echo -e "${RED}❌ Node.js version $NODE_VERSION is too old. Please install version $REQUIRED_VERSION or later.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Node.js version $NODE_VERSION detected${NC}"

# Create service user and group
echo -e "${YELLOW}📝 Creating service user and group...${NC}"
if ! getent group $SERVICE_GROUP >/dev/null 2>&1; then
    groupadd --system $SERVICE_GROUP
    echo -e "${GREEN}✅ Created group: $SERVICE_GROUP${NC}"
fi

if ! getent passwd $SERVICE_USER >/dev/null 2>&1; then
    useradd --system --gid $SERVICE_GROUP --home-dir $INSTALL_DIR --shell /bin/false $SERVICE_USER
    echo -e "${GREEN}✅ Created user: $SERVICE_USER${NC}"
fi

# Create directories
echo -e "${YELLOW}📁 Creating directories...${NC}"
mkdir -p $INSTALL_DIR
mkdir -p $LOG_DIR
mkdir -p $CONFIG_DIR
chown $SERVICE_USER:$SERVICE_GROUP $INSTALL_DIR
chown $SERVICE_USER:$SERVICE_GROUP $LOG_DIR
chown root:$SERVICE_GROUP $CONFIG_DIR
chmod 755 $CONFIG_DIR

# Copy application files
echo -e "${YELLOW}📦 Installing application files...${NC}"
cp -r * $INSTALL_DIR/
chown -R $SERVICE_USER:$SERVICE_GROUP $INSTALL_DIR

# Install dependencies
echo -e "${YELLOW}📚 Installing Node.js dependencies...${NC}"
cd $INSTALL_DIR
sudo -u $SERVICE_USER npm install --production --silent

# Copy configuration files
echo -e "${YELLOW}⚙️  Setting up configuration...${NC}"
if [ -f "$INSTALL_DIR/config/default.json" ]; then
    cp $INSTALL_DIR/config/default.json $CONFIG_DIR/
    chown root:$SERVICE_GROUP $CONFIG_DIR/default.json
    chmod 640 $CONFIG_DIR/default.json
fi

if [ -f "$INSTALL_DIR/.env.example" ]; then
    cp $INSTALL_DIR/.env.example $CONFIG_DIR/env.example
    if [ ! -f "$CONFIG_DIR/.env" ]; then
        cp $INSTALL_DIR/.env.example $CONFIG_DIR/.env
        chown root:$SERVICE_GROUP $CONFIG_DIR/.env
        chmod 640 $CONFIG_DIR/.env
    fi
fi

# Create symlink for config
ln -sf $CONFIG_DIR/.env $INSTALL_DIR/.env

# Install systemd service
echo -e "${YELLOW}🔧 Installing systemd service...${NC}"
cp $INSTALL_DIR/systemd/postgresql-fyi.service /etc/systemd/system/
systemctl daemon-reload

# Set up log rotation
echo -e "${YELLOW}📋 Setting up log rotation...${NC}"
cat > /etc/logrotate.d/postgresql-fyi << EOF
$LOG_DIR/*.log {
    daily
    rotate 1
    compress
    delaycompress
    missingok
    notifempty
    create 644 $SERVICE_USER $SERVICE_GROUP
    postrotate
        systemctl reload $SERVICE_NAME
    endscript
}
EOF

# Create startup script for manual use
echo -e "${YELLOW}📜 Creating management scripts...${NC}"
cat > /usr/local/bin/postgresql-fyi << 'EOF'
#!/bin/bash
case "$1" in
    start)
        sudo systemctl start postgresql-fyi
        ;;
    stop)
        sudo systemctl stop postgresql-fyi
        ;;
    restart)
        sudo systemctl restart postgresql-fyi
        ;;
    status)
        systemctl status postgresql-fyi
        ;;
    logs)
        journalctl -u postgresql-fyi -f
        ;;
    enable)
        sudo systemctl enable postgresql-fyi
        ;;
    disable)
        sudo systemctl disable postgresql-fyi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|enable|disable}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/postgresql-fyi

# Set permissions
chmod +x $INSTALL_DIR/server.js
chmod +x $INSTALL_DIR/scripts/*.sh

echo -e "${GREEN}✅ Installation completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "1. Edit configuration: sudo nano $CONFIG_DIR/.env"
echo "2. Start the service: sudo systemctl start postgresql-fyi"
echo "3. Enable auto-start: sudo systemctl enable postgresql-fyi"
echo "4. Check status: systemctl status postgresql-fyi"
echo "5. View logs: journalctl -u postgresql-fyi -f"
echo ""
echo -e "${BLUE}🎛️  Quick Commands:${NC}"
echo "postgresql-fyi start    # Start the service"
echo "postgresql-fyi stop     # Stop the service"
echo "postgresql-fyi status   # Check status"
echo "postgresql-fyi logs     # View logs"
echo ""
echo -e "${BLUE}🌐 Default Configuration:${NC}"
echo "Service will run on: http://localhost:6240"
echo "Edit $CONFIG_DIR/.env to change settings"
echo ""
echo -e "${GREEN}🎉 Ready to use! The service is now installed.${NC}"
