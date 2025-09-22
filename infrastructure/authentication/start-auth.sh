#!/bin/bash

# CyberHub Authentication Server Start Script
# Manages Keycloak identity provider for CyberHub

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

show_help() {
    cat << EOF
CyberHub Authentication Server (Keycloak)

Usage: $0 [OPTIONS]

OPTIONS:
    --detach, -d        Run in background (default)
    --foreground        Run in foreground
    --help, -h          Show this help message

ENDPOINTS:
    Keycloak Admin: http://localhost:8180/admin
    Default credentials: admin / admin

EOF
}

# Default values
DETACH=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --detach|-d)
            DETACH=true
            shift
            ;;
        --foreground)
            DETACH=false
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
print_info "Starting CyberHub Authentication Server..."

# Check if .env exists
if [ ! -f ".env" ]; then
    print_warning "No .env file found. Using default values."
fi

# Start services
if [ "$DETACH" = true ]; then
    docker compose up -d
else
    docker compose up
fi

if [ "$DETACH" = true ]; then
    print_success "Authentication server started successfully!"
    echo
    print_info "Service Information:"
    echo "  • Keycloak Admin Console: http://localhost:8180/admin"
    echo "  • Default Credentials: admin / admin"
    echo "  • Database: PostgreSQL (internal)"
    echo
    print_info "Useful Commands:"
    echo "  • View logs: docker logs -f cyberhub-keycloak"
    echo "  • Stop services: ./stop-auth.sh"
    echo "  • Check status: docker ps | grep cyberhub-keycloak"
fi