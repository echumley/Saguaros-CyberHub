#!/bin/bash

# CyberCore User Profiles Stop Script
# Stops all services and optionally cleans up volumes

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
COMPOSE_FILE="user-postgresql-compose.yml"
REMOVE_VOLUMES=false
REMOVE_NETWORK=false

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
CyberCore User Profiles Stop Script

Usage: $0 [OPTIONS]

OPTIONS:
    --remove-volumes    Remove Docker volumes (WARNING: This deletes all data!)
    --remove-network    Remove the Docker network
    --help, -h          Show this help message

EXAMPLES:
    $0                  Stop services but keep data
    $0 --remove-volumes Complete cleanup including database data
    $0 --remove-network Stop and remove network (use if no other services need it)

WARNING:
    Using --remove-volumes will permanently delete all database data!
EOF
}

# Function to stop services
stop_services() {
    print_info "Stopping CyberCore User Profiles services..."
    
    # Stop using the main compose file
    if [ -f "user-postgresql-compose.yml" ]; then
        print_info "Stopping services from user-postgresql-compose.yml"
        
        # Use docker compose if available, fallback to docker-compose
        if docker compose version &> /dev/null; then
            docker compose -f "user-postgresql-compose.yml" down 2>/dev/null || true
        else
            docker-compose -f "user-postgresql-compose.yml" down 2>/dev/null || true
        fi
    fi
    
    # Also try to stop containers by name in case compose files are missing
    print_info "Ensuring individual containers are stopped..."
    docker stop cybercore-postgres 2>/dev/null || true
    docker stop ldap-sync 2>/dev/null || true
    
    print_success "Services stopped"
}

# Function to remove volumes
remove_volumes() {
    if [ "$REMOVE_VOLUMES" = true ]; then
        print_warning "Removing Docker volumes (this will delete all data)..."
        
        # Remove named volumes
        docker volume rm db_data 2>/dev/null || true
        docker volume rm dirsync_cookies 2>/dev/null || true
        docker volume rm cybercore_db_data 2>/dev/null || true
        docker volume rm cybercore_dirsync_cookies 2>/dev/null || true
        
        # Remove any anonymous volumes
        print_info "Removing unused volumes..."
        docker volume prune -f
        
        print_success "Volumes removed"
    fi
}

# Function to remove network
remove_network() {
    if [ "$REMOVE_NETWORK" = true ]; then
        print_info "Removing Docker network..."
        
        if docker network inspect cybercore-net &> /dev/null; then
            docker network rm cybercore-net
            print_success "Network removed"
        else
            print_info "Network doesn't exist or already removed"
        fi
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    print_info "Cleaning up temporary files..."
    
    # Remove .env file if it exists
    if [ -f ".env" ]; then
        rm -f ".env"
        print_info "Removed temporary .env file"
    fi
    
    # Clean up any other temporary files
    rm -f .env.tmp 2>/dev/null || true
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
    print_info "Stopping CyberCore User Profiles..."
    
    if [ "$REMOVE_VOLUMES" = true ]; then
        print_warning "Volume removal is enabled - all data will be deleted!"
        echo -n "Are you sure? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Operation cancelled"
            exit 0
        fi
    fi
    
    # Stop services
    stop_services
    
    # Remove volumes if requested
    remove_volumes
    
    # Remove network if requested
    remove_network
    
    # Clean up temporary files
    cleanup_temp_files
    
    print_success "CyberCore User Profiles stopped successfully!"
    
    if [ "$REMOVE_VOLUMES" = false ]; then
        print_info "Database data has been preserved"
        print_info "To completely remove all data, run: $0 --remove-volumes"
    fi
}

# Run main function
main "$@"
