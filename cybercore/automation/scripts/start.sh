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
NO_DETACH=false
FORCE_RECREATE=false
ENABLE_TLS=false

# Function to display help
show_help() {
    cat << EOF
CyberCore Integrated Stack - Start Script

Usage: $0 [OPTIONS]

Options:
    --no-detach         Run in foreground to see live logs
    --force-recreate    Force recreate containers even if they exist
    --tls               Enable TLS/HTTPS for all services
    --help              Show this help message

Environment Variables:
    DB_PASSWORD         PostgreSQL password (default: change_me_local)
    N8N_ENCRYPTION_KEY  n8n encryption key (32+ chars, generated if not set)

Examples:
    # Start services
    $0

    # Start in foreground
    $0 --no-detach

    # Force recreate containers
    $0 --force-recreate

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-detach)
            NO_DETACH=true
            shift
            ;;
        --force-recreate)
            FORCE_RECREATE=true
            shift
            ;;
        --tls)
            ENABLE_TLS=true
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

# Create necessary directories
mkdir -p automation/scripts
mkdir -p n8n/workflows
mkdir -p n8n/credentials

# Generate n8n encryption key if not set
if [ -z "${N8N_ENCRYPTION_KEY:-}" ]; then
    echo -e "${YELLOW}Generating n8n encryption key...${NC}"
    export N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
    echo "N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY" >> .env.generated
    echo -e "${GREEN}Generated key saved to .env.generated${NC}"
fi

# Set environment variables

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cat > .env << EOF
# CyberCore Environment Configuration
# Generated on $(date)

# Database
DB_PASSWORD=change_me_local


# n8n
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY:-dev-only-change-me-32-chars-min}
N8N_WEBHOOK_URL=http://localhost:5678

# Timezone
TZ=America/Phoenix
EOF
    echo -e "${GREEN}Created .env file with default configuration${NC}"
fi

# Display configuration
echo -e "${GREEN}Starting CyberCore Integrated Stack${NC}"
echo "Configuration:"
echo "  - Compose file: $COMPOSE_FILE"
echo "  - TLS Enabled: $ENABLE_TLS"
echo ""

# Build docker-compose command
COMPOSE_CMD="docker compose -f $COMPOSE_FILE"

# Add force-recreate flag if requested
if [ "$FORCE_RECREATE" = true ]; then
    COMPOSE_CMD="$COMPOSE_CMD up --force-recreate"
else
    COMPOSE_CMD="$COMPOSE_CMD up"
fi

# Add detach flag unless --no-detach was specified
if [ "$NO_DETACH" = false ]; then
    COMPOSE_CMD="$COMPOSE_CMD -d"
fi

# Start the services
echo -e "${YELLOW}Starting services...${NC}"
eval $COMPOSE_CMD

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Services started successfully!${NC}"
    echo ""
    echo "Service URLs:"
    echo "  - n8n UI:        http://localhost:5678"
    echo "  - Adminer:       http://localhost:8080"
    echo "  - PostgreSQL:    localhost:5432"
    echo "  - Redis:         localhost:6379"

    # Show logs command
    echo ""
    echo "To view logs:"
    echo "  docker compose -f $COMPOSE_FILE logs -f [service_name]"
    echo ""
    echo "Service names: postgres, redis, n8n-webhook, n8n-worker, adminer"

else
    echo -e "${RED}Failed to start services${NC}"
    exit 1
fi