#!/bin/bash

# CyberHub Authentication Server Stop Script

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
CyberHub Authentication Server Stop Script

Usage: $0 [OPTIONS]

OPTIONS:
    --remove-volumes    Remove data volumes (WARNING: Deletes all data!)
    --help, -h          Show this help message

EOF
}

# Default values
REMOVE_VOLUMES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remove-volumes)
            REMOVE_VOLUMES=true
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
print_info "Stopping CyberHub Authentication Server..."

if [ "$REMOVE_VOLUMES" = true ]; then
    print_warning "Removing volumes - all data will be deleted!"
    docker compose down -v
else
    docker compose down
fi

print_success "Authentication server stopped successfully!"

if [ "$REMOVE_VOLUMES" = false ]; then
    print_info "Data has been preserved. Use --remove-volumes to delete all data."
fi