#!/bin/bash

set -euo pipefail

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# CyberCore root is two directories up from scripts/
CYBERCORE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$CYBERCORE_ROOT"

# Default values
COMPOSE_FILE="$CYBERCORE_ROOT/automation/docker/cybercore-compose.yml"
REMOVE_VOLUMES=false
REMOVE_NETWORK=false

# Function to display help
show_help() {
    cat << EOF
CyberCore Integrated Stack - Stop Script

Usage: $0 [OPTIONS]

Options:
    --remove-volumes    Remove Docker volumes (WARNING: Deletes all data!)
    --remove-network    Remove the Docker network
    --tls              Use TLS compose file
    --help             Show this help message

Examples:
    # Stop services (keep data)
    $0

    # Stop services and remove all data
    $0 --remove-volumes

    # Complete cleanup
    $0 --remove-volumes --remove-network

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remove-volumes)
            REMOVE_VOLUMES=true
            shift
            ;;
        --remove-network)
            REMOVE_NETWORK=true
            shift
            ;;
        --tls)
            COMPOSE_FILE="$CYBERCORE_ROOT/automation/docker/cybercore-compose-tls.yml"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Check for required files
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${RED}Error: Compose file '$COMPOSE_FILE' not found${NC}"
    exit 1
fi

echo -e "${YELLOW}Stopping CyberCore Integrated Stack...${NC}"

# Stop containers
docker compose -f $COMPOSE_FILE down

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Services stopped successfully${NC}"
else
    echo -e "${RED}Failed to stop some services${NC}"
fi

# Remove volumes if requested
if [ "$REMOVE_VOLUMES" = true ]; then
    echo -e "${YELLOW}WARNING: Removing all Docker volumes (this will delete all data!)${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        docker compose -f $COMPOSE_FILE down -v
        echo -e "${GREEN}Volumes removed${NC}"
    else
        echo -e "${YELLOW}Volume removal cancelled${NC}"
    fi
fi

# Remove network if requested
if [ "$REMOVE_NETWORK" = true ]; then
    echo -e "${YELLOW}Removing Docker network...${NC}"
    docker network rm cybercore-net 2>/dev/null || true
    echo -e "${GREEN}Network removed${NC}"
fi

# Clean up generated files
if [ -f .env.generated ]; then
    echo -e "${YELLOW}Removing generated environment file...${NC}"
    rm -f .env.generated
fi

echo -e "${GREEN}CyberCore Integrated Stack stopped${NC}"