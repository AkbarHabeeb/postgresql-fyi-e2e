#!/bin/bash

# PostgreSQL FYI Service - Manual Start Script
# Usage: ./scripts/start.sh [options]

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Default values
PORT=1234
HOST=localhost
CORS_ORIGINS="*"
LOG_LEVEL=info
DEV_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -h|--host)
            HOST="$2"
            shift 2
            ;;
        --cors-origins)
            CORS_ORIGINS="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --dev)
            DEV_MODE=true
            NODE_ENV=development
            shift
            ;;
        --help)
            echo "PostgreSQL FYI Service - Manual Start"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -p, --port PORT         Port to run on (default: 1234)"
            echo "  -h, --host HOST         Host to bind to (default: localhost)"
            echo "      --cors-origins      CORS origins (default: *)"
            echo "      --log-level LEVEL   Log level (default: info)"
            echo "      --dev               Development mode"
            echo "      --help              Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --port 9000 --cors-origins \"https://myapp.com\""
            echo "  $0 --dev --log-level debug"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set environment variables
export PORT=$PORT
export HOST=$HOST
export CORS_ORIGINS=$CORS_ORIGINS
export LOG_LEVEL=$LOG_LEVEL
export NODE_ENV=${NODE_ENV:-production}

# For development mode, use local log file instead of system path
if [ "$DEV_MODE" = true ]; then
    mkdir -p logs
    export LOG_FILE="./logs/service.log"
else
    export LOG_FILE="/var/log/postgresql-fyi/service.log"
fi

echo -e "${GREEN}🐘 Starting PostgreSQL FYI Service${NC}"
echo "=================================="
echo -e "Port: ${YELLOW}$PORT${NC}"
echo -e "Host: ${YELLOW}$HOST${NC}"
echo -e "CORS Origins: ${YELLOW}$CORS_ORIGINS${NC}"
echo -e "Log Level: ${YELLOW}$LOG_LEVEL${NC}"
echo -e "Environment: ${YELLOW}$NODE_ENV${NC}"
echo -e "Log File: ${YELLOW}$LOG_FILE${NC}"
echo ""

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "server.js" ]; then
    echo -e "${RED}❌ server.js not found. Please run this script from the postgresql-fyi directory${NC}"
    exit 1
fi

# Install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    npm install
fi

# Start the service
echo -e "${GREEN}🚀 Starting service...${NC}"
echo ""

if [ "$DEV_MODE" = true ]; then
    # Development mode with nodemon if available
    if command -v nodemon &> /dev/null; then
        nodemon server.js
    else
        node server.js
    fi
else
    node server.js
fi