#!/bin/bash

# Keycloak Docker Entrypoint Script
# This script runs inside the Keycloak container to perform initial setup

set -e

echo "Starting Keycloak initialization..."

# Wait for database to be ready
until pg_isready -h keycloak-db -p 5432 -U ${KC_DB_USERNAME}; do
  echo "Waiting for database..."
  sleep 2
done

echo "Database is ready!"

# Start Keycloak in background
/opt/keycloak/bin/kc.sh start &
KC_PID=$!

# Wait for Keycloak to be ready
echo "Waiting for Keycloak to start..."
until curl -fsS http://localhost:8080/health/ready > /dev/null 2>&1; do
  sleep 5
done

echo "Keycloak is ready!"

# Check if realm already exists
REALM_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $(curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
    -d "username=${KC_BOOTSTRAP_ADMIN_USERNAME}" \
    -d "password=${KC_BOOTSTRAP_ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)" \
  http://localhost:8080/admin/realms/cybercore)

if [ "$REALM_EXISTS" != "200" ]; then
  echo "Performing initial setup..."
  
  # Run setup script
  if [ -f /opt/keycloak/setup/keycloak-setup.sh ]; then
    bash /opt/keycloak/setup/keycloak-setup.sh
  fi
  
  # Configure LDAP if environment variables are set
  if [ -n "$LDAP_CONNECTION_URL" ] && [ -n "$LDAP_BIND_DN" ] && [ -n "$LDAP_BIND_PASSWORD" ]; then
    echo "Configuring LDAP..."
    python3 /opt/keycloak/setup/configure-ldap.py
  fi
else
  echo "Realm already exists, skipping setup"
fi

# Keep Keycloak running
wait $KC_PID