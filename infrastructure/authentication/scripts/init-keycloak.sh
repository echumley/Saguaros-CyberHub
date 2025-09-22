#!/bin/bash

# CyberCore Keycloak Initialization Script
# Initializes Keycloak with realm, users, and federation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KC_SERVER="${KC_SERVER:-http://auth.localhost:8080}"
KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
KC_ADMIN_PASS="${KC_ADMIN_PASS:-admin}"
REALM_NAME="${REALM_NAME:-cybercore}"
DB_HOST="${DB_HOST:-cybercore-postgres}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-cyberhub_core}"
DB_USER="${DB_USER:-cyberhub}"
DB_PASS="${DB_PASS:-cyberpass}"

# LDAP Configuration (optional)
LDAP_ENABLED="${LDAP_ENABLED:-false}"
LDAP_URI="${LDAP_URI:-}"
LDAP_BASE_DN="${LDAP_BASE_DN:-}"
LDAP_BIND_DN="${LDAP_BIND_DN:-}"
LDAP_BIND_PW="${LDAP_BIND_PW:-}"
LDAP_TYPE="${LDAP_TYPE:-activedirectory}"

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

# Wait for PostgreSQL to be ready
wait_for_postgres() {
    print_info "Waiting for PostgreSQL..."
    MAX_ATTEMPTS=30
    ATTEMPT=0
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if PGPASSWORD=$DB_PASS psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "SELECT 1" > /dev/null 2>&1; then
            print_success "PostgreSQL is ready!"
            return 0
        fi
        ATTEMPT=$((ATTEMPT + 1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS..."
        sleep 2
    done
    
    print_error "PostgreSQL failed to start"
    return 1
}

# Initialize database schema
init_database() {
    print_info "Initializing database schema..."
    
    # Check if keycloak-init.sql exists
    INIT_SQL="/app/keycloak-init.sql"
    if [ ! -f "$INIT_SQL" ]; then
        INIT_SQL="/cybercore/data/db/keycloak-init.sql"
    fi
    
    if [ -f "$INIT_SQL" ]; then
        PGPASSWORD=$DB_PASS psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f "$INIT_SQL"
        print_success "Database schema initialized"
    else
        print_warning "Database init script not found, skipping..."
    fi
}

# Wait for Keycloak to be ready
wait_for_keycloak() {
    print_info "Waiting for Keycloak..."
    MAX_ATTEMPTS=60
    ATTEMPT=0
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if curl -fsS "${KC_SERVER}" > /dev/null 2>&1; then
            print_success "Keycloak is ready!"
            return 0
        fi
        ATTEMPT=$((ATTEMPT + 1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS..."
        sleep 5
    done
    
    print_error "Keycloak failed to start"
    return 1
}

# Run Python integration script
run_integration() {
    print_info "Running Keycloak integration..."
    
    # Install Python dependencies
    pip install --quiet psycopg2-binary requests
    
    # Export environment variables for Python script
    export KC_SERVER DB_HOST DB_PORT DB_NAME DB_USER DB_PASS
    export LDAP_ENABLED LDAP_URI LDAP_BASE_DN LDAP_BIND_DN LDAP_BIND_PW LDAP_TYPE
    
    # Run the Python integration script
    INTEGRATION_SCRIPT="/app/keycloak-integration.py"
    if [ ! -f "$INTEGRATION_SCRIPT" ]; then
        INTEGRATION_SCRIPT="/cybercore/automation/scripts/keycloak-integration.py"
    fi
    
    if [ -f "$INTEGRATION_SCRIPT" ]; then
        python3 "$INTEGRATION_SCRIPT"
        print_success "Keycloak integration complete"
    else
        print_error "Integration script not found"
        return 1
    fi
}

# Main execution
main() {
    print_info "Starting CyberCore Keycloak Initialization..."
    
    # Wait for services
    wait_for_postgres || exit 1
    
    # Initialize database
    init_database
    
    # Wait for Keycloak
    wait_for_keycloak || exit 1
    
    # Run integration
    run_integration || exit 1
    
    print_success "=" * 50
    print_success "Keycloak Initialization Complete!"
    print_info "Access Points:"
    print_info "  - Keycloak Admin: ${KC_SERVER}/admin"
    print_info "  - Username: ${KC_ADMIN_USER}"
    print_info "  - Password: ${KC_ADMIN_PASS}"
    print_info "  - Realm: ${REALM_NAME}"
    print_success "=" * 50
}

# Run main function
main "$@"