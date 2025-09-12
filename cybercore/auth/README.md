# Keycloak Authentication Integration

This directory contains the Keycloak authentication integration for CyberCore, providing centralized identity and access management with LDAP/Active Directory support.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  CyberCore  │────▶│   Keycloak   │────▶│  LDAP/AD     │
│    Apps     │     │   (Auth)     │     │  (Future)    │
└─────────────┘     └──────────────┘     └──────────────┘
       │                    │                     │
       ▼                    ▼                     ▼
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│   Traefik   │     │  PostgreSQL  │     │    Users     │
│   (Proxy)   │     │  (KC Data)   │     │   (Source)   │
└─────────────┘     └──────────────┘     └──────────────┘
```

## Quick Start

### 1. Start Keycloak with CyberCore

```bash
# From the cybercore directory
docker-compose up -d

# Services will be available at:
# - Keycloak: http://auth.localhost:8080
# - CyberCore: http://localhost:8080
# - N8n: http://n8n.localhost:8080
```

### 2. Run Initial Setup

```bash
# Wait for services to start, then run setup
cd auth/
./keycloak-setup.sh
```

This creates:
- CyberCore realm
- Default client configuration
- Groups: administrators, operators, users, read-only
- Roles: admin, operator, viewer, api-access
- Test user: testuser/testpass

### 3. Configure LDAP (Optional)

For Active Directory or OpenLDAP integration:

```bash
# Interactive configuration
python3 configure-ldap.py

# Or set environment variables for automated setup
export LDAP_CONNECTION_URL="ldaps://ad.example.com:636"
export LDAP_BIND_DN="CN=Service,OU=Accounts,DC=example,DC=com"
export LDAP_BIND_PASSWORD="your-password"
```

## Configuration

### Environment Variables

Add to `cybercore/.env`:

```env
# Keycloak Configuration
KC_HOSTNAME=auth.localhost
KC_ADMIN_USER=admin
KC_ADMIN_PASS=admin
KC_DB_NAME=keycloak
KC_DB_USER=keycloak
KC_DB_PASS=keycloak
KC_LOG_LEVEL=INFO

# LDAP Configuration (optional)
LDAP_CONNECTION_URL=ldaps://ad.example.com:636
LDAP_BIND_DN=CN=Service,OU=Accounts,DC=example,DC=com
LDAP_BIND_PASSWORD=your-password
LDAP_USERS_DN=DC=example,DC=com
LDAP_VENDOR=ad  # ad, openldap, other
```

### Keycloak Endpoints

- Admin Console: http://auth.localhost:8080/admin
- Account Console: http://auth.localhost:8080/realms/cybercore/account
- OpenID Discovery: http://auth.localhost:8080/realms/cybercore/.well-known/openid-configuration

### Client Configuration

Default client settings for CyberCore:
- Client ID: `cybercore`
- Client Secret: `cybercore-secret`
- Grant Types: authorization_code, refresh_token, client_credentials
- Redirect URIs: http://localhost:8080/*, http://cybercore.localhost/*

## Integration with CyberCore

### Python Integration Example

```python
from keycloak import KeycloakOpenID

# Configure client
keycloak_openid = KeycloakOpenID(
    server_url="http://auth.localhost:8080",
    client_id="cybercore",
    realm_name="cybercore",
    client_secret_key="cybercore-secret"
)

# Get token
token = keycloak_openid.token("testuser", "testpass")

# Verify token
userinfo = keycloak_openid.userinfo(token['access_token'])

# Logout
keycloak_openid.logout(token['refresh_token'])
```

### API Protection

Use the included middleware for protecting endpoints:

```python
from modules.keycloak_auth import KeycloakClient, require_auth

# Initialize client
kc_config = {
    'server_url': 'http://auth.localhost:8080',
    'realm': 'cybercore',
    'client_id': 'cybercore',
    'client_secret': 'cybercore-secret'
}
keycloak = KeycloakClient(kc_config)

# Protect endpoints
@require_auth(keycloak)
def protected_endpoint(user=None):
    return f"Hello {user['preferred_username']}"
```

## LDAP Integration

### Active Directory Setup

1. Configure in Keycloak Admin Console or use script:
```bash
python3 configure-ldap.py
# Select option 1 for Active Directory
```

2. Required information:
- LDAP URL (ldaps://ad.example.com:636)
- Bind DN (service account)
- Bind Password
- Users DN (search base)

3. Sync settings:
- Full sync: Weekly by default
- Incremental sync: Daily by default
- Import users: Enabled
- Edit mode: Read-only

### OpenLDAP Setup

1. Configure in Keycloak Admin Console or use script:
```bash
python3 configure-ldap.py
# Select option 2 for OpenLDAP
```

2. Attribute mappings are pre-configured for standard schemas

### Manual LDAP Configuration

Access Keycloak Admin Console:
1. Navigate to User Federation
2. Add provider → LDAP
3. Configure connection settings
4. Set up attribute mappers
5. Test connection and sync

## Security Considerations

### Production Deployment

1. **Change default passwords** in `.env`:
   - KC_ADMIN_PASS
   - KC_DB_PASS
   - Client secrets

2. **Enable HTTPS**:
   - Set KC_HOSTNAME to your domain
   - Configure SSL certificates in Traefik
   - Set KC_HTTP_ENABLED=false

3. **Network Security**:
   - Restrict database access
   - Use internal networks for service communication
   - Configure firewall rules

4. **LDAP Security**:
   - Use LDAPS (port 636) or StartTLS
   - Use dedicated service accounts with minimal permissions
   - Enable certificate validation

### Backup and Recovery

```bash
# Backup Keycloak database
docker exec cybercore-keycloak-db pg_dump -U keycloak keycloak > keycloak_backup.sql

# Restore Keycloak database
docker exec -i cybercore-keycloak-db psql -U keycloak keycloak < keycloak_backup.sql

# Export realm configuration
docker exec cybercore-keycloak \
  /opt/keycloak/bin/kc.sh export \
  --dir /tmp/export \
  --realm cybercore

# Import realm configuration
docker exec cybercore-keycloak \
  /opt/keycloak/bin/kc.sh import \
  --dir /tmp/export
```

## Troubleshooting

### Common Issues

1. **Keycloak won't start**
   - Check logs: `docker logs cybercore-keycloak`
   - Verify database is running: `docker ps | grep keycloak-db`
   - Check port conflicts: `netstat -an | grep 8080`

2. **LDAP connection fails**
   - Verify network connectivity to LDAP server
   - Check bind DN and password
   - Ensure service account has read permissions
   - Test with ldapsearch: `ldapsearch -x -H ldaps://server -D "binddn" -w password`

3. **Users can't authenticate**
   - Check user exists in Keycloak
   - Verify client configuration
   - Check realm settings
   - Review logs for authentication errors

### Debug Mode

Enable debug logging:
```bash
# In docker-compose.yml or .env
KC_LOG_LEVEL=DEBUG

# Restart Keycloak
docker-compose restart keycloak
```

## Scripts Reference

### keycloak-setup.sh
Automated setup script for initial Keycloak configuration.

### configure-ldap.py
Interactive LDAP configuration tool supporting Active Directory and OpenLDAP.

### docker-entrypoint.sh
Container initialization script for automated setup during deployment.

## Support

For issues or questions:
1. Check Keycloak logs: `docker logs cybercore-keycloak`
2. Review this documentation
3. Consult [Keycloak documentation](https://www.keycloak.org/documentation)
4. Open an issue in the CyberCore repository