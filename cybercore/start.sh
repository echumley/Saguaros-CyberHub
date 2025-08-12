#!/bin/bash

# CyberCore Start Script
# Starts Traefik, PostgreSQL database, N8N, Adminer, and LDAP sync services

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
COMPOSE_FILE="cybercore-compose.yml"
SERVICE_NAME="ldap-sync"
DETACH=true
FORCE_RECREATE=false
USE_UNIVERSAL=false
LDAP_TYPE="activedirectory"
TEMP_DIR="/tmp/cybercore-$$"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show help
show_help() {
    cat << EOF
CyberCore Start Script

Usage: $0 [OPTIONS]

OPTIONS:
    --dry-run           Run in dry-run mode (mock LDAP connection)
    --no-detach         Run in foreground (don't detach containers)
    --force-recreate    Force recreate containers even if they exist
    --universal         Use universal LDAP connector (supports AD, OpenLDAP, 389DS)
    --ldap-type TYPE    Set LDAP server type (activedirectory, openldap, 389ds, auto)
    --openldap          Shortcut for --universal --ldap-type openldap
    --help, -h          Show this help message

EXAMPLES:
        ./start.sh                          Start normally with AD-optimized connector
    $0 --dry-run                Start with mock LDAP data (no real LDAP server needed)
    $0 --universal              Use universal connector with Active Directory
    $0 --openldap               Use universal connector with OpenLDAP
    $0 --universal --ldap-type 389ds  Use universal connector with 389 Directory Server
    $0 --no-detach              Start in foreground to see live logs
    $0 --dry-run --no-detach --force-recreate
                                Start in dry-run mode, foreground, recreating containers

SERVICES:
    - Traefik reverse proxy (localhost:8080)
    - PostgreSQL database (cybercore-postgres)
    - N8N automation platform (n8n.localhost:8080)
    - Adminer web interface (adminer.localhost:8080)
    - LDAP Sync service (user synchronization)

LDAP CONNECTORS:
    AD-Optimized Connector:   High-performance Active Directory sync
    Universal Connector:      Supports AD, OpenLDAP, 389DS with auto-detection

ENVIRONMENT:
    The script will create the required Docker network if it doesn't exist.
    In dry-run mode, the DRY_RUN environment variable is set to 'true'.
EOF
}

# Function to check requirements
check_requirements() {
    print_info "Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not available"
        exit 1
    fi
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    if [ ! -f "automation/scripts/universal-ldap-sync.py" ]; then
        print_error "Universal LDAP sync script not found: automation/scripts/universal-ldap-sync.py"
        exit 1
    fi
    
    print_success "All requirements met"
}

# Function to create Docker network if it doesn't exist
create_network() {
    print_info "Checking Docker network..."
    
    if ! docker network inspect cybercore-net &> /dev/null; then
        print_info "Creating Docker network: cybercore-net"
        docker network create cybercore-net
        print_success "Network created"
    else
        print_info "Network already exists: cybercore-net"
    fi
}

# Function to create environment file for dry-run mode
create_dry_run_env() {
    print_info "Setting up dry-run mode environment variables..." >&2
    
    # Create temporary directory for runtime files
    mkdir -p "$TEMP_DIR"
    
    # Create temporary .env file with dry-run settings
    cat > "$TEMP_DIR/.env" << 'EOF'
# Dry-run mode settings
DRY_RUN=true
INTERVAL=10
LOG_LEVEL=INFO
INCLUDE_DELETES=true
EOF

    # Add connector-specific settings
    cat >> "$TEMP_DIR/.env" << EOF
SYNC_PAGE_SIZE=2000
LDAP_TYPE=${LDAP_TYPE}
EOF

    # Add database settings (same for both modes)
    cat >> "$TEMP_DIR/.env" << 'EOF'

# Database settings (same for both modes)
DB_HOST=cybercore-postgres
DB_PORT=5432
DB_NAME=cyberhub_core
DB_USER=cyberhub
DB_PASS=cyberpass
EOF

    print_success "Dry-run environment configured in $TEMP_DIR" >&2
}

# Function to start services
start_services() {
    local compose_file=$1
    local detach_flag=""
    local recreate_flag=""
    local profile_flag=""
    local env_file_flag=""
    
    if [ "$DETACH" = true ]; then
        detach_flag="-d"
    fi
    
    if [ "$FORCE_RECREATE" = true ]; then
        recreate_flag="--force-recreate"
    fi
    
    # Use temporary .env file if it exists
    if [ -f "$TEMP_DIR/.env" ]; then
        env_file_flag="--env-file $TEMP_DIR/.env"
        print_info "Using temporary environment file: $TEMP_DIR/.env"
    elif [ -f ".env" ]; then
        print_info "Using existing .env file"
    else
        print_info "Using compose file defaults (no .env file)"
    fi
    
    # Determine which profile to use
    if [ "$USE_UNIVERSAL" = false ]; then
        # Use ad-optimized profile for the legacy AD connector
        profile_flag="--profile ad-optimized"
    else
        # Use universal profile for multi-platform LDAP connector
        profile_flag="--profile universal"
    fi

    print_info "Starting services..."
    print_info "Compose file: $compose_file"
    print_info "Detach mode: $DETACH"
    print_info "Force recreate: $FORCE_RECREATE"
    print_info "Profile: ${profile_flag:-none}"
    
    # Use docker compose if available, fallback to docker-compose
    if docker compose version &> /dev/null; then
        docker compose -f "$compose_file" $env_file_flag $profile_flag up $detach_flag $recreate_flag
    else
        docker-compose -f "$compose_file" $env_file_flag $profile_flag up $detach_flag $recreate_flag
    fi
}

# Function to show service status and info
show_service_info() {
    print_success "Services started successfully!"
    echo
    print_info "Service Information:"
    echo "  • PostgreSQL Database:"
    echo "    - Host: localhost:5433"
    echo "    - Database: cyberhub_core"
    echo "    - Username: cyberhub"
    echo "    - Password: cyberpass"
    echo
    echo "  • Adminer Web Interface:"
    echo "    - URL: http://adminer.localhost:8080"
    echo "    - Use the database credentials above to connect"
    echo
    echo "  • N8N Automation Platform:"
    echo "    - URL: http://n8n.localhost:8080"
    echo "    - Webhook URL: http://n8n.localhost:8080/"
    echo
    echo "  • Traefik Reverse Proxy:"
    echo "    - Dashboard: http://localhost:8080 (if API enabled)"
    echo "    - HTTP Entry Point: localhost:8080"
    echo
    echo "  • LDAP Sync Service:"
    if [ "$DRY_RUN" = true ]; then
        echo "    - Mode: DRY-RUN (mock LDAP data)"
        echo "    - Interval: 10 seconds"
        echo "    - Status: Generating test user data"
        echo "    - Connector: Universal LDAP Sync (${LDAP_TYPE})"
    else
        echo "    - Mode: PRODUCTION (Universal LDAP Connector)"
        echo "    - LDAP Type: ${LDAP_TYPE}"
        echo "    - Interval: 30 seconds"
        echo "    - Status: Synchronizing with LDAP server"
    fi
    echo
    print_info "Useful Commands:"
    echo "  • View logs: docker logs -f cybercore-postgres"
    echo "  • View n8n logs: docker logs -f [n8n-container-name]"
    echo "  • View sync logs: docker logs -f cybercore-ldap-sync (or cybercore-universal-ldap-sync)"
    echo "  • Stop services: docker compose -f $COMPOSE_FILE down"
    echo "  • Connect to database: docker exec -it cybercore-postgres psql -U cyberhub -d cyberhub_core"
    echo
}

# Function to cleanup
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        print_info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-detach)
            DETACH=false
            shift
            ;;
        --force-recreate)
            FORCE_RECREATE=true
            shift
            ;;
        --universal)
            USE_UNIVERSAL=true
            shift
            ;;
        --ldap-type)
            LDAP_TYPE="$2"
            shift 2
            ;;
        --openldap)
            USE_UNIVERSAL=true
            LDAP_TYPE="openldap"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

    # Main execution
main() {
    print_info "Starting CyberCore services..."
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "Running in DRY-RUN mode (mock LDAP connection)"
    else
        print_info "Running in PRODUCTION mode (real LDAP connection)"
    fi
    
    if [ "$USE_UNIVERSAL" = true ]; then
        print_info "Using Universal LDAP Connector (${LDAP_TYPE})"
    else
        print_info "Using AD-Optimized Connector (Active Directory)"
    fi
    
    # Check requirements
    check_requirements
    
    # Create network
    create_network
    
    # Determine configuration approach
    if [ "$DRY_RUN" = true ]; then
        create_dry_run_env
    else
        # Create production .env in temp dir if using universal connector
        if [ "$USE_UNIVERSAL" = true ]; then
            mkdir -p "$TEMP_DIR"
            cat > "$TEMP_DIR/.env" << EOF
LDAP_TYPE=${LDAP_TYPE}
EOF
            print_info "Created temporary production .env with LDAP_TYPE=${LDAP_TYPE}"
        fi
    fi    # Start services with the appropriate compose file
    start_services "$COMPOSE_FILE"
    
    # Show information if running detached
    if [ "$DETACH" = true ]; then
        show_service_info
    fi
}

# Run main function
main "$@"
