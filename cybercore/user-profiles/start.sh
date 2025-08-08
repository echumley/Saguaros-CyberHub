#!/bin/bash

# CyberCore User Profiles Start Script
# Starts the PostgreSQL database and DirSync service

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
COMPOSE_FILE="user-postgresql-compose.yml"
SERVICE_NAME="ldap-sync"
DETACH=true
FORCE_RECREATE=false
USE_UNIVERSAL=false
LDAP_TYPE="activedirectory"

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
CyberCore User Profiles Start Script

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
    $0                          Start normally with legacy AD connector
    $0 --dry-run                Start with mock LDAP data (no real LDAP server needed)
    $0 --universal              Use universal connector with Active Directory
    $0 --openldap               Use universal connector with OpenLDAP
    $0 --universal --ldap-type 389ds  Use universal connector with 389 Directory Server
    $0 --no-detach              Start in foreground to see live logs
    $0 --dry-run --no-detach --force-recreate
                                Start in dry-run mode, foreground, recreating containers

SERVICES:
    - PostgreSQL database (cybercore-postgres)
    - Adminer web interface (localhost:8080)
    - LDAP Sync service (user synchronization)

LDAP CONNECTORS:
    Legacy Connector:     Optimized for Active Directory only (DirSync)
    Universal Connector:  Supports AD, OpenLDAP, 389DS with auto-detection

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
    
    if [ ! -f "dirsync.py" ]; then
        print_error "DirSync script not found: dirsync.py"
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
    
    # Create or update .env file with dry-run settings
    cat > .env << 'EOF'
# Dry-run mode settings
DRY_RUN=true
INTERVAL=10
LOG_LEVEL=INFO
INCLUDE_DELETES=true
EOF

    # Add connector-specific settings
    if [ "$USE_UNIVERSAL" = true ]; then
        cat >> .env << EOF
SYNC_PAGE_SIZE=2000
LDAP_TYPE=${LDAP_TYPE}
EOF
    else
        cat >> .env << 'EOF'
DIRSYNC_PAGE_SIZE=2000
EOF
    fi

    # Add database settings (same for both modes)
    cat >> .env << 'EOF'

# Database settings (same for both modes)
DB_HOST=cybercore-postgres
DB_PORT=5432
DB_NAME=cyberhub_core
DB_USER=cyberhub
DB_PASS=cyberpass
EOF

    print_success "Dry-run environment configured" >&2
}

# Function to start services
start_services() {
    local compose_file=$1
    local detach_flag=""
    local recreate_flag=""
    
    if [ "$DETACH" = true ]; then
        detach_flag="-d"
    fi
    
    if [ "$FORCE_RECREATE" = true ]; then
        recreate_flag="--force-recreate"
    fi
    
    print_info "Starting services..."
    print_info "Compose file: $compose_file"
    print_info "Detach mode: $DETACH"
    print_info "Force recreate: $FORCE_RECREATE"
    
    # Use docker compose if available, fallback to docker-compose
    if docker compose version &> /dev/null; then
        docker compose -f "$compose_file" up $detach_flag $recreate_flag
    else
        docker-compose -f "$compose_file" up $detach_flag $recreate_flag
    fi
}

# Function to show service status and info
show_service_info() {
    print_success "Services started successfully!"
    echo
    print_info "Service Information:"
    echo "  • PostgreSQL Database:"
    echo "    - Host: localhost:5432"
    echo "    - Database: cyberhub_core"
    echo "    - Username: cyberhub"
    echo "    - Password: cyberpass"
    echo
    echo "  • Adminer Web Interface:"
    echo "    - URL: http://localhost:8080"
    echo "    - Use the database credentials above to connect"
    echo
    echo "  • DirSync Service:"
    if [ "$DRY_RUN" = true ]; then
        echo "    - Mode: DRY-RUN (mock LDAP data)"
        echo "    - Interval: 10 seconds"
        echo "    - Status: Generating test user data"
        if [ "$USE_UNIVERSAL" = true ]; then
            echo "    - Connector: Universal (${LDAP_TYPE})"
        else
            echo "    - Connector: Legacy (Active Directory)"
        fi
    else
        if [ "$USE_UNIVERSAL" = true ]; then
            echo "    - Mode: PRODUCTION (Universal LDAP Connector)"
            echo "    - LDAP Type: ${LDAP_TYPE}"
            echo "    - Interval: 30 seconds"
            echo "    - Status: Synchronizing with LDAP server"
        else
            echo "    - Mode: PRODUCTION (Legacy AD Connector)"
            echo "    - LDAP Server: ldaps://ad-1.saguaroscyberhub.org"
            echo "    - Interval: 30 seconds"
            echo "    - Status: Synchronizing with Active Directory"
        fi
    fi
    echo
    print_info "Useful Commands:"
    echo "  • View logs: docker logs -f cybercore-postgres"
    echo "  • View sync logs: docker logs -f ldap-sync (or container name)"
    echo "  • Stop services: docker-compose -f $COMPOSE_FILE down"
    echo "  • Connect to database: docker exec -it cybercore-postgres psql -U cyberhub -d cyberhub_core"
    echo
}

# Function to cleanup
cleanup() {
    if [ "$DRY_RUN" = true ] && [ -f ".env" ]; then
        print_info "Cleaning up temporary environment file..."
        rm -f .env
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
            COMPOSE_FILE="universal-compose.yml"
            shift
            ;;
        --ldap-type)
            LDAP_TYPE="$2"
            shift 2
            ;;
        --openldap)
            USE_UNIVERSAL=true
            LDAP_TYPE="openldap"
            COMPOSE_FILE="universal-compose.yml"
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
    print_info "Starting CyberCore User Profiles..."
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "Running in DRY-RUN mode (mock LDAP connection)"
    else
        print_info "Running in PRODUCTION mode (real LDAP connection)"
    fi
    
    if [ "$USE_UNIVERSAL" = true ]; then
        print_info "Using Universal LDAP Connector (${LDAP_TYPE})"
    else
        print_info "Using Legacy AD Connector (Active Directory only)"
    fi
    
    # Check requirements
    check_requirements
    
    # Create network
    create_network
    
    # Determine configuration approach
    if [ "$DRY_RUN" = true ]; then
        create_dry_run_env
    else
        # Remove any existing .env file to use defaults
        rm -f .env
        
        # Create production .env if using universal connector
        if [ "$USE_UNIVERSAL" = true ]; then
            cat > .env << EOF
LDAP_TYPE=${LDAP_TYPE}
EOF
        fi
    fi
    
    # Start services with the appropriate compose file
    start_services "$COMPOSE_FILE"
    
    # Show information if running detached
    if [ "$DETACH" = true ]; then
        show_service_info
    fi
}

# Run main function
main "$@"
