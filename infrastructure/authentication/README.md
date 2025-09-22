# CyberHub Authentication Server

Centralized identity and access management using Keycloak, separate from CyberCore services.

## Architecture

This is the CyberHub-wide authentication server, providing:
- Single Sign-On (SSO) for all CyberHub modules
- Identity federation (LDAP/AD/SAML/OAuth)
- User and group management
- Fine-grained authorization

## Quick Start

```bash
# Start the authentication server
./start-auth.sh

# Stop the server
./stop-auth.sh

# Remove all data
./stop-auth.sh --remove-volumes
```

## Access

- **Admin Console**: http://localhost:8180/admin
- **Default Credentials**: admin / admin
- **Port**: 8180 (to avoid conflicts with CyberCore on 8080)

## Configuration

Edit `.env` file for:
- Admin credentials
- Database settings
- LDAP integration
- Hostname configuration

## Integration with CyberCore

CyberCore can be configured to use this authentication server for:
1. User authentication via OAuth2/OIDC
2. API authorization
3. Service-to-service authentication

## Directory Structure

```
authentication/
├── docker-compose.yml    # Keycloak and database services
├── .env                 # Environment configuration
├── data/               # Persistent data
│   └── keycloak-db/   # PostgreSQL data
├── configs/           # Realm and client configurations
├── scripts/          # Integration and setup scripts
├── start-auth.sh    # Start script
├── stop-auth.sh    # Stop script
└── README.md       # This file
```

## LDAP Federation

To enable LDAP/Active Directory federation:
1. Edit `.env` with your LDAP settings
2. Configure in Keycloak Admin Console:
   - User Federation → Add Provider → LDAP
   - Configure connection and sync settings

## Security Notes

- Change default admin password immediately
- Use HTTPS in production (configure reverse proxy)
- Enable 2FA for admin accounts
- Regular backups of `data/` directory

## Troubleshooting

### View logs
```bash
docker logs -f cyberhub-keycloak
docker logs -f cyberhub-keycloak-db
```

### Reset admin password
```bash
docker exec cyberhub-keycloak /opt/keycloak/bin/kc.sh admin set-password --username admin
```

### Database connection
```bash
docker exec -it cyberhub-keycloak-db psql -U keycloak
```

## Migration from CyberCore

If migrating from integrated Keycloak in CyberCore:
1. Export realm from old instance
2. Import to this server
3. Update CyberCore to use external auth server
4. Configure network connectivity between services