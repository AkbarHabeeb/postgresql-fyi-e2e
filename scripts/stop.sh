#!/bin/bash

# PostgreSQL FYI Service - Stop Script
# Usage: ./scripts/stop.sh

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🛑 Stopping PostgreSQL FYI Service${NC}"

# Try to stop systemd service first
if systemctl is-active --quiet postgresql-fyi; then
    echo -e "${YELLOW}Stopping systemd service...${NC}"
    sudo systemctl stop postgresql-fyi
    echo -e "${GREEN}✅ Systemd service stopped${NC}"
    exit 0
fi

# Find and kill process by name
PIDS=$(pgrep -f "node.*server.js")

if [ -z "$PIDS" ]; then
    echo -e "${YELLOW}No PostgreSQL FYI Service processes found${NC}"
    exit 0
fi

echo -e "${YELLOW}Found process(es): $PIDS${NC}"

# Send SIGTERM first (graceful shutdown)
echo -e "${YELLOW}Sending SIGTERM for graceful shutdown...${NC}"
kill -TERM $PIDS

# Wait for graceful shutdown
sleep 5

# Check if processes are still running
REMAINING_PIDS=$(pgrep -f "node.*server.js")

if [ -z "$REMAINING_PIDS" ]; then
    echo -e "${GREEN}✅ Service stopped gracefully${NC}"
    exit 0
fi

# Force kill if still running
echo -e "${YELLOW}Processes still running, sending SIGKILL...${NC}"
kill -KILL $REMAINING_PIDS

sleep 2

# Final check
FINAL_PIDS=$(pgrep -f "node.*server.js")

if [ -z "$FINAL_PIDS" ]; then
    echo -e "${GREEN}✅ Service stopped (forced)${NC}"
else
    echo -e "${RED}❌ Failed to stop some processes: $FINAL_PIDS${NC}"
    exit 1
fi