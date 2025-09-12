#!/bin/bash

# Keycloak Setup Script for CyberCore
# This script configures Keycloak with realms, clients, and LDAP integration

set -e

# Configuration
KC_SERVER="${KC_SERVER:-http://auth.localhost:8080}"
KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
KC_ADMIN_PASS="${KC_ADMIN_PASS:-admin}"
REALM_NAME="${REALM_NAME:-cybercore}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== CyberCore Keycloak Setup ===${NC}"

# Wait for Keycloak to be ready
echo -e "${YELLOW}Waiting for Keycloak to be ready...${NC}"
MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -fsS "${KC_SERVER}/health/ready" > /dev/null 2>&1; then
        echo -e "${GREEN}Keycloak is ready!${NC}"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${RED}Keycloak failed to start after $MAX_ATTEMPTS attempts${NC}"
    exit 1
fi

# Get admin token
echo -e "${YELLOW}Getting admin token...${NC}"
TOKEN_RESPONSE=$(curl -s -X POST "${KC_SERVER}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${KC_ADMIN_USER}" \
    -d "password=${KC_ADMIN_PASS}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli")

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}Failed to get admin token${NC}"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo -e "${GREEN}Successfully obtained admin token${NC}"

# Create CyberCore realm
echo -e "${YELLOW}Creating CyberCore realm...${NC}"
REALM_JSON='{
  "realm": "'${REALM_NAME}'",
  "enabled": true,
  "displayName": "CyberCore",
  "displayNameHtml": "<b>CyberCore</b>",
  "loginTheme": "keycloak",
  "accountTheme": "keycloak.v2",
  "adminTheme": "keycloak",
  "emailTheme": "keycloak",
  "sslRequired": "external",
  "registrationAllowed": false,
  "registrationEmailAsUsername": false,
  "rememberMe": true,
  "verifyEmail": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "permanentLockout": false,
  "maxFailureWaitSeconds": 900,
  "minimumQuickLoginWaitSeconds": 60,
  "waitIncrementSeconds": 60,
  "quickLoginCheckMilliSeconds": 1000,
  "maxDeltaTimeSeconds": 43200,
  "failureFactor": 30,
  "defaultSignatureAlgorithm": "RS256",
  "offlineSessionMaxLifespanEnabled": false,
  "offlineSessionMaxLifespan": 5184000,
  "clientSessionIdleTimeout": 0,
  "clientSessionMaxLifespan": 0,
  "clientOfflineSessionIdleTimeout": 0,
  "clientOfflineSessionMaxLifespan": 0,
  "accessTokenLifespan": 300,
  "accessTokenLifespanForImplicitFlow": 900,
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 36000,
  "ssoSessionIdleTimeoutRememberMe": 0,
  "ssoSessionMaxLifespanRememberMe": 0,
  "offlineSessionIdleTimeout": 2592000,
  "accessCodeLifespan": 60,
  "accessCodeLifespanUserAction": 300,
  "accessCodeLifespanLogin": 1800,
  "actionTokenGeneratedByAdminLifespan": 43200,
  "actionTokenGeneratedByUserLifespan": 300,
  "browserSecurityHeaders": {
    "contentSecurityPolicyReportOnly": "",
    "xContentTypeOptions": "nosniff",
    "referrerPolicy": "no-referrer",
    "xRobotsTag": "none",
    "xFrameOptions": "SAMEORIGIN",
    "contentSecurityPolicy": "frame-src '\''self'\''; frame-ancestors '\''self'\''; object-src '\''none'\'';",
    "xXSSProtection": "1; mode=block",
    "strictTransportSecurity": "max-age=31536000; includeSubDomains"
  },
  "smtpServer": {},
  "eventsEnabled": true,
  "eventsListeners": ["jboss-logging"],
  "enabledEventTypes": [
    "SEND_RESET_PASSWORD",
    "UPDATE_CONSENT_ERROR",
    "LOGIN",
    "CLIENT_LOGIN",
    "LOGOUT",
    "REGISTER",
    "DELETE_ACCOUNT",
    "UPDATE_PASSWORD",
    "LOGIN_ERROR",
    "CLIENT_LOGIN_ERROR",
    "LOGOUT_ERROR",
    "REGISTER_ERROR",
    "UPDATE_PASSWORD_ERROR"
  ],
  "adminEventsEnabled": true,
  "adminEventsDetailsEnabled": true,
  "internationalizationEnabled": false,
  "supportedLocales": [],
  "browserFlow": "browser",
  "registrationFlow": "registration",
  "directGrantFlow": "direct grant",
  "resetCredentialsFlow": "reset credentials",
  "clientAuthenticationFlow": "clients",
  "dockerAuthenticationFlow": "docker auth",
  "attributes": {},
  "userManagedAccessAllowed": false
}'

REALM_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KC_SERVER}/admin/realms" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${REALM_JSON}")

if [ "$REALM_RESPONSE" = "201" ] || [ "$REALM_RESPONSE" = "409" ]; then
    echo -e "${GREEN}CyberCore realm created/exists${NC}"
else
    echo -e "${RED}Failed to create realm. Response code: $REALM_RESPONSE${NC}"
fi

# Create CyberCore client
echo -e "${YELLOW}Creating CyberCore client...${NC}"
CLIENT_JSON='{
  "clientId": "cybercore",
  "name": "CyberCore Application",
  "description": "Main CyberCore application client",
  "rootUrl": "http://localhost:8080",
  "adminUrl": "http://localhost:8080",
  "baseUrl": "/",
  "surrogateAuthRequired": false,
  "enabled": true,
  "alwaysDisplayInConsole": false,
  "clientAuthenticatorType": "client-secret",
  "secret": "cybercore-secret",
  "redirectUris": [
    "http://localhost:8080/*",
    "http://cybercore.localhost/*",
    "http://localhost:3000/*"
  ],
  "webOrigins": [
    "http://localhost:8080",
    "http://cybercore.localhost",
    "http://localhost:3000"
  ],
  "notBefore": 0,
  "bearerOnly": false,
  "consentRequired": false,
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": true,
  "publicClient": false,
  "frontchannelLogout": false,
  "protocol": "openid-connect",
  "attributes": {
    "oidc.ciba.grant.enabled": "false",
    "oauth2.device.authorization.grant.enabled": "false",
    "display.on.consent.screen": "false",
    "backchannel.logout.session.required": "true",
    "backchannel.logout.revoke.offline.tokens": "false"
  },
  "authenticationFlowBindingOverrides": {},
  "fullScopeAllowed": true,
  "nodeReRegistrationTimeout": -1,
  "protocolMappers": [
    {
      "name": "email",
      "protocol": "openid-connect",
      "protocolMapper": "oidc-usermodel-property-mapper",
      "consentRequired": false,
      "config": {
        "userinfo.token.claim": "true",
        "user.attribute": "email",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "claim.name": "email",
        "jsonType.label": "String"
      }
    },
    {
      "name": "username",
      "protocol": "openid-connect",
      "protocolMapper": "oidc-usermodel-property-mapper",
      "consentRequired": false,
      "config": {
        "userinfo.token.claim": "true",
        "user.attribute": "username",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "claim.name": "preferred_username",
        "jsonType.label": "String"
      }
    },
    {
      "name": "groups",
      "protocol": "openid-connect",
      "protocolMapper": "oidc-group-membership-mapper",
      "consentRequired": false,
      "config": {
        "full.path": "false",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "claim.name": "groups",
        "userinfo.token.claim": "true"
      }
    }
  ],
  "defaultClientScopes": [
    "web-origins",
    "acr",
    "profile",
    "roles",
    "email"
  ],
  "optionalClientScopes": [
    "address",
    "phone",
    "offline_access",
    "microprofile-jwt"
  ]
}'

CLIENT_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KC_SERVER}/admin/realms/${REALM_NAME}/clients" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${CLIENT_JSON}")

if [ "$CLIENT_RESPONSE" = "201" ] || [ "$CLIENT_RESPONSE" = "409" ]; then
    echo -e "${GREEN}CyberCore client created/exists${NC}"
else
    echo -e "${RED}Failed to create client. Response code: $CLIENT_RESPONSE${NC}"
fi

# Create default groups
echo -e "${YELLOW}Creating default groups...${NC}"
GROUPS=("administrators" "operators" "users" "read-only")

for GROUP in "${GROUPS[@]}"; do
    GROUP_JSON='{"name": "'${GROUP}'"}'
    GROUP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KC_SERVER}/admin/realms/${REALM_NAME}/groups" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${GROUP_JSON}")
    
    if [ "$GROUP_RESPONSE" = "201" ] || [ "$GROUP_RESPONSE" = "409" ]; then
        echo -e "${GREEN}  Group '${GROUP}' created/exists${NC}"
    else
        echo -e "${RED}  Failed to create group '${GROUP}'. Response code: $GROUP_RESPONSE${NC}"
    fi
done

# Create default roles
echo -e "${YELLOW}Creating default roles...${NC}"
ROLES=("admin" "operator" "viewer" "api-access")

for ROLE in "${ROLES[@]}"; do
    ROLE_JSON='{"name": "'${ROLE}'", "composite": false, "clientRole": false}'
    ROLE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KC_SERVER}/admin/realms/${REALM_NAME}/roles" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${ROLE_JSON}")
    
    if [ "$ROLE_RESPONSE" = "201" ] || [ "$ROLE_RESPONSE" = "409" ]; then
        echo -e "${GREEN}  Role '${ROLE}' created/exists${NC}"
    else
        echo -e "${RED}  Failed to create role '${ROLE}'. Response code: $ROLE_RESPONSE${NC}"
    fi
done

# Create a test user
echo -e "${YELLOW}Creating test user...${NC}"
TEST_USER_JSON='{
  "username": "testuser",
  "email": "testuser@cybercore.local",
  "emailVerified": true,
  "enabled": true,
  "firstName": "Test",
  "lastName": "User",
  "credentials": [
    {
      "type": "password",
      "value": "testpass",
      "temporary": false
    }
  ],
  "groups": ["users"]
}'

USER_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KC_SERVER}/admin/realms/${REALM_NAME}/users" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${TEST_USER_JSON}")

if [ "$USER_RESPONSE" = "201" ] || [ "$USER_RESPONSE" = "409" ]; then
    echo -e "${GREEN}Test user created/exists${NC}"
else
    echo -e "${RED}Failed to create test user. Response code: $USER_RESPONSE${NC}"
fi

echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${YELLOW}Access Keycloak at: ${KC_SERVER}${NC}"
echo -e "${YELLOW}Admin Console: ${KC_SERVER}/admin${NC}"
echo -e "${YELLOW}Realm: ${REALM_NAME}${NC}"
echo -e "${YELLOW}Test User: testuser / testpass${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Configure LDAP integration in Keycloak admin console"
echo "2. Update CyberCore application to use Keycloak authentication"
echo "3. Test authentication flow"