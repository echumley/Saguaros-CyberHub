# 🧠 CyberCore: The Central Brain of CyberHub

## 🔗 Responsibilities:
* User provisioning & identity mapping (via LDAP/Keycloak)
* Profile DB (badges, VMs, progress, achievements)
* Inter-module orchestration via webhooks or API calls
* Audit logs & activity tracking
* Triggering and monitoring workflows across modules via n8n

## Flowchart

flowchart TD
    A[User logs in via Keycloak]
    A --> B[Hub redirects to Dashboard UI]
    B --> C[Dashboard fetches profile data via FastAPI API]
    C --> D[FastAPI queries PostgreSQL]
    C --> E[FastAPI sends update to n8n via webhook or DB write]
    F[CyberLabs, Crucible, University] --> E

# CyberCore User Profiles - LDAP Synchronization Service

The LDAP synchronization service keeps your PostgreSQL users table synchronized with various LDAP servers including Active Directory, OpenLDAP, and 389 Directory Server. 

## Connector Options

- **AD-Optimized Connector**: High-performance Active Directory sync using Microsoft's DirSync control for efficient delta synchronization
- **Universal LDAP Connector**: Supports multiple LDAP server types (Active Directory, OpenLDAP, 389DS) with automatic server detection and appropriate sync strategies

# Quick Start

### AD-Optimized Active Directory Connector
```bash
# Start all services with optimized AD sync
./start.sh

# Stop services (keeps data)
./stop.sh

# Complete cleanup (removes all data)
./stop.sh --remove-volumes
```

### Universal LDAP Connector (Supports AD, OpenLDAP, 389DS)
```bash
# Start with universal connector (auto-detects server type)
./start.sh --universal

# Start with specific LDAP server types
./start.sh --openldap                    # OpenLDAP shortcut
./start.sh --universal --ldap-type 389ds # 389 Directory Server
./start.sh --universal --ldap-type auto  # Auto-detection (default)

# Stop services
./stop.sh
```

### Development/Testing Mode (Mock LDAP)
```bash
# Start in dry-run mode with mock data (works with both connectors)
./start.sh --dry-run
./start.sh --universal --dry-run

# Run in foreground to see logs
./start.sh --dry-run --no-detach

# Force recreate containers
./start.sh --dry-run --force-recreate
```

# CyberCore User Profiles - Usage Examples

This file contains common usage patterns for the start and stop scripts

✅ DUAL CONNECTOR SUPPORT: Legacy AD + Universal LDAP

1. DEVELOPMENT/TESTING (Dry-run mode):
  `./start.sh --dry-run              # Legacy AD connector with mock data`
  `./start.sh --universal --dry-run  # Universal connector with mock data`
  `./start.sh --openldap --dry-run   # OpenLDAP connector with mock data`
  `./start.sh --dry-run --no-detach  # Start in foreground to see logs`
  `./stop.sh                         # Stop services, keep data`

2. PRODUCTION - Active Directory:
  `./start.sh                        # Legacy AD connector (DirSync optimized)`
  `./start.sh --universal            # Universal connector (compatible mode)`
  `./stop.sh                         # Stop services, keep data`

3. PRODUCTION - OpenLDAP:
  `./start.sh --openldap             # Universal connector for OpenLDAP`
  `./start.sh --universal --ldap-type openldap  # Same as above`

4. PRODUCTION - 389 Directory Server:
  `./start.sh --universal --ldap-type 389ds     # 389DS support`

5. AUTO-DETECTION:
  `./start.sh --universal --ldap-type auto      # Auto-detect LDAP server type`

6. DEBUGGING:
  `./start.sh --no-detach            # Start in foreground`
  `./start.sh --force-recreate       # Force rebuild containers`

7. COMPLETE CLEANUP:
  `./stop.sh --remove-volumes        # Stop and DELETE ALL DATA`
  `./stop.sh --remove-network        # Also remove Docker network`

8. MONITORING:
  `docker logs -f cybercore-postgres                    # Database logs`
  `docker logs -f cybercore-ldap-sync                   # Legacy AD connector logs`
  `docker logs -f cybercore-universal-ldap-sync         # Universal connector logs`
  `docker exec -it cybercore-postgres psql -U cyberhub -d cyberhub_core  # Connect to DB`

9. WEB INTERFACE:
  open `http://localhost:8080`        # Adminer database web UI
  # Use: Server=cybercore-postgres, User=cyberhub, Password=cyberpass, Database=cyberhub_core

### Connector Comparison
**Legacy AD Connector:**
✅ Optimized for Active Directory (DirSync control)
✅ Maximum performance for large AD environments
❌ Active Directory only

**Universal Connector:**
✅ Supports AD, OpenLDAP, 389DS, auto-detection
✅ Consistent interface across LDAP servers
✅ Future-proof for new LDAP server types
✅ AD optimized with DirSync

### Service Overview
PostgreSQL:    localhost:5432 (cyberhub_core database)
Adminer:       localhost:8080 (database web interface)
LDAP Sync:     Background service (user synchronization)

Run `./start.sh --help` or `./stop.sh --help` for detailed options.

## Services Included

When you run `./start.sh`, the following services are started:

1. **PostgreSQL Database** (`cybercore-postgres`)
   - Port: 5432
   - Database: cyberhub_core
   - Username: cyberhub
   - Password: cyberpass

2. **Adminer Web Interface**
   - URL: http://localhost:8080
   - Use database credentials above to connect

3. **LDAP Sync Service**
   - **AD-Optimized Mode**: `ldap-sync` - High-performance Active Directory synchronization using DirSync
   - **Universal Mode**: `universal-ldap-sync` - Multi-platform LDAP support (AD, OpenLDAP, 389DS)
   - In dry-run mode: generates mock test data
   - In production mode: connects to real LDAP server

## Connector Comparison

| Feature | AD-Optimized Connector | Universal LDAP Connector |
|---------|-------------------|--------------------------|
| Active Directory | ✅ Optimized DirSync | ✅ Standard LDAP queries |
| OpenLDAP | ❌ | ✅ Timestamp-based sync |
| 389 Directory Server | ❌ | ✅ nsAccountLock support |
| Auto-detection | ❌ | ✅ Server type detection |
| Delta Sync | ✅ DirSync cookies | ✅ Timestamp/cookie based |
| Performance | ⭐⭐⭐ (AD only) | ⭐⭐ (Good for all) |

## Script Options

### start.sh Options
- `--universal`: Use universal LDAP connector (supports AD, OpenLDAP, 389DS)
- `--ldap-type TYPE`: Set LDAP server type (activedirectory, openldap, 389ds, auto)
- `--openldap`: Shortcut for `--universal --ldap-type openldap`
- `--dry-run`: Run with mock LDAP data (no real LDAP server needed)
- `--no-detach`: Run in foreground to see live logs
- `--force-recreate`: Force recreate containers even if they exist
- `--help`: Show help message

### stop.sh Options
- `--remove-volumes`: Remove Docker volumes (WARNING: Deletes all data!)
- `--remove-network`: Remove the Docker network
- `--help`: Show help message

## Environment Variables

### Universal Connector Settings
```bash
# LDAP Server Configuration
LDAP_URI=ldaps://your-server.example.com      # LDAP server URL
LDAP_BASE_DN=DC=example,DC=com                 # Search base DN
LDAP_BIND_DN=CN=svc-sync,OU=Service Accounts,DC=example,DC=com  # Bind DN
LDAP_BIND_PW=your_service_account_password     # Bind password
LDAP_TYPE=auto                                 # Server type (auto, activedirectory, openldap, 389ds)

# OpenLDAP Specific (when LDAP_TYPE=openldap)
LDAP_USER_FILTER=(objectClass=inetOrgPerson)   # User search filter
LDAP_TIMESTAMP_ATTR=modifyTimestamp           # Sync timestamp attribute
```

### AD-Optimized Connector Settings
```bash
# Active Directory Configuration (AD-optimized connector)
LDAP_URI=ldaps://your-dc.example.com          # Domain Controller URL
LDAP_BASE_DN=DC=example,DC=com                # Search base DN
LDAP_BIND_DN=CN=svc-dirsync,OU=Service Accounts,DC=example,DC=com  # Service account DN
LDAP_BIND_PW=your_service_account_password    # Service account password
```

### Required PostgreSQL Settings
```bash
PGHOST=your-postgres-host                    # Default: localhost
PGPORT=5432                                  # Default: 5432
PGDATABASE=your_database_name                # Required
PGUSER=your_username                         # Required
PGPASSWORD=your_password                     # Required
```

### Optional Settings
```bash
# General Settings
LOG_LEVEL=INFO                               # Default: INFO (DEBUG, INFO, WARNING, ERROR)
INTERVAL=30                                  # Sync interval in seconds (default: 30)
DRY_RUN=false                               # Enable dry-run mode (default: false)

# AD-Optimized Connector Specific
DIRSYNC_PAGE_SIZE=2000                      # Max objects per query (default: 2000)
INCLUDE_DELETES=false                       # Include AD tombstones (default: false)
DIRSYNC_COOKIE_FILE=/app/.dirsync_cookie    # Cookie storage path (default: /app/.dirsync_cookie)

# Universal Connector Specific
SYNC_STATE_FILE=/app/sync_state.json       # State persistence file (default: /app/sync_state.json)
```

## LDAP Server Configuration

### Active Directory
- **Recommended Connector**: AD-optimized connector for maximum performance
- **Universal Connector**: Supported with standard LDAP queries
- **Prerequisites**: Service account with read permissions, LDAPS connectivity
- **Features**: User status detection via `userAccountControl`, account expiration, lockout status

### OpenLDAP
- **Connector**: Universal connector only
- **Sync Strategy**: Timestamp-based using `modifyTimestamp`
- **User Filter**: `(objectClass=inetOrgPerson)` (configurable)
- **Status Detection**: Based on account attributes and operational status

### 389 Directory Server
- **Connector**: Universal connector only  
- **Sync Strategy**: Timestamp-based with 389DS-specific attributes
- **Status Detection**: Uses `nsAccountLock` attribute for account status
- **Features**: Native Red Hat/CentOS directory server support

## Dry-Run Mode

The service includes a dry-run mode for development and testing:

### Features
- **No LDAP server required**: Generates mock user data
- **Simulates real scenarios**: User creation, status changes, deletions
- **Progressive changes**: Different data on each sync iteration
- **Full database integration**: Tests the complete pipeline except LDAP

### Mock Data Scenarios
The dry-run mode simulates realistic Active Directory scenarios:

1. **Initial sync**: Creates base set of users (Alice, Bob, Carol)
2. **Status changes**: Bob gets disabled after iteration 3
3. **New users**: David is added after iteration 5  
4. **User deletions**: Alice is marked deleted after iteration 8 (if INCLUDE_DELETES=true)
5. **Different user states**: Active, inactive, suspended accounts

### Usage
```bash
# AD-optimized connector dry-run mode
./start.sh --dry-run

# Universal connector dry-run mode
./start.sh --universal --dry-run

# Or set environment variable manually
export DRY_RUN=true
python3 dirsync.py           # AD-optimized connector
python3 universal_ldap_sync.py  # Universal connector
```

### Testing Benefits
- **Safe testing**: No risk of affecting production AD
- **Faster iteration**: No network delays or LDAP setup required
- **Predictable data**: Consistent test scenarios for development
- **Status validation**: Test all user status transitions

## Database Schema
Ensure your PostgreSQL database has this table structure:

```sql
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,        -- sAMAccountName
  email TEXT,
  first_name TEXT,
  last_name TEXT,
  full_name TEXT,
  ldap_dn TEXT UNIQUE,
  active BOOLEAN DEFAULT TRUE,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended', 'banned', 'deleted')),
  last_ldap_sync TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP NULL             -- Track when user was deleted in AD
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_ldap_dn ON users(ldap_dn);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
```

## User Status Types

The service now tracks detailed user status based on Active Directory attributes:

- **`active`**: Normal, functioning user accounts
- **`inactive`**: Disabled accounts or expired accounts 
- **`suspended`**: Accounts that are locked out (temporary restriction)
- **`banned`**: Accounts with password restrictions (permanent restriction)
- **`deleted`**: Tombstone objects from AD Recycle Bin

### Status Determination Logic

The service examines these LDAP attributes to determine status:

- **`isDeleted`**: If true → `deleted`
- **`userAccountControl`**: 
  - Bit 2 set (UF_ACCOUNTDISABLE) → `inactive`
  - Bit 16 set (UF_LOCKOUT) → `suspended`
  - Complex password expiry flags → `banned`
- **`accountExpires`**: If expired → `inactive`
- **`lockoutTime`**: If currently locked → `suspended`
- **Default**: `active` if no negative indicators

## Docker Deployment

### AD-Optimized Connector
```yaml
ldap-sync:
  image: python:3.11-slim
  restart: unless-stopped
  environment:
    LDAP_URI: ldaps://your-dc.example.com
    LDAP_BASE_DN: DC=example,DC=com
    LDAP_BIND_DN: CN=svc-dirsync,OU=Service Accounts,DC=example,DC=com
    LDAP_BIND_PW: your_password
    # ... other environment variables
  volumes:
    - ./dirsync.py:/app/dirsync.py:ro
    - ./cookies:/app/cookies
  command: ["python", "/app/dirsync.py"]
  networks:
    - cybercore-net
```

### Universal LDAP Connector
```yaml
universal-ldap-sync:
  image: python:3.11-slim
  restart: unless-stopped
  environment:
    LDAP_URI: ldaps://your-server.example.com
    LDAP_BASE_DN: DC=example,DC=com
    LDAP_BIND_DN: CN=svc-sync,OU=Service Accounts,DC=example,DC=com
    LDAP_BIND_PW: your_password
    LDAP_TYPE: auto  # or activedirectory, openldap, 389ds
    # ... other environment variables
  volumes:
    - ./universal_ldap_sync.py:/app/universal_ldap_sync.py:ro
    - sync_state:/app/sync_state
  command: ["python", "/app/universal_ldap_sync.py"]
  networks:
    - cybercore-net
```

## Prerequisites by LDAP Server

### Active Directory
#### For Basic Sync
- Service account with read permissions to the user container
- LDAP/LDAPS connectivity to domain controllers

#### For Deleted User Detection (Optional)
- AD Recycle Bin enabled on the domain
- Service account with "List Deleted Objects" permission
- Set `INCLUDE_DELETES=true` (AD-optimized connector only)

### OpenLDAP
- LDAP service account with read access to user entries
- LDAPS recommended for production
- Users must have `modifyTimestamp` operational attribute
- Common user object class: `inetOrgPerson`

### 389 Directory Server
- Service account with read permissions
- LDAPS connectivity recommended
- Access to `nsAccountLock` attribute for status detection
- Standard LDAP user object classes

## Monitoring & Logs

The service logs all operations:
- **INFO**: Successful sync operations, user counts
- **DEBUG**: Detailed iteration information, empty sync cycles  
- **WARNING**: LDAP search failures
- **ERROR**: Database errors, individual iteration failures
- **CRITICAL**: Fatal startup errors

## Performance Notes

### AD-Optimized Connector
- **DirSync Cookie**: Enables delta sync - only changed objects are returned
- **Page Size**: Adjust `DIRSYNC_PAGE_SIZE` based on your AD size (default 2000 is good for most)
- **Optimal Performance**: Designed specifically for Active Directory environments

### Universal Connector  
- **Auto-Detection**: Automatically detects server type and optimizes accordingly
- **Timestamp Sync**: Uses `modifyTimestamp` for OpenLDAP and 389DS delta sync
- **State Persistence**: Maintains sync state in JSON file for resumable operations
- **Multi-Server**: Good performance across different LDAP server types

### General
- **Sync Interval**: 30 seconds is reasonable for most environments
- **Network**: LDAPS recommended for production
- **Connection Resilience**: Both connectors include 15-second retry logic for connection failures

## Troubleshooting

### Common Issues
1. **Authentication failures**: 
   - Check BIND_DN format (use NTLM `domain\user` format for AD if needed)
   - Verify service account credentials
   - Test LDAP connectivity: `ldapsearch -H $LDAP_URI -D "$LDAP_BIND_DN" -W`

2. **Permission errors**: 
   - Ensure service account has proper LDAP read permissions
   - For AD: Check "Read" and "List Contents" permissions on user containers
   - For OpenLDAP/389DS: Verify ACLs allow read access to user attributes

3. **Certificate errors**: 
   - Verify LDAPS certificate trust
   - Check certificate validity and chain
   - Consider using `LDAP_REQUIRE_CERT=never` for testing (not production)

4. **Database connection**: 
   - Check PostgreSQL connectivity and credentials
   - Verify database schema exists
   - Test connection: `psql -h $PGHOST -U $PGUSER -d $PGDATABASE`

5. **Server Type Detection Issues**:
   - Universal connector: Check `LDAP_TYPE` setting
   - Force specific type: `--ldap-type activedirectory|openldap|389ds`
   - Review auto-detection logs for schema analysis

### Log Analysis
- **AD-optimized connector**: Monitor cookie length changes to verify delta sync is working
- **Universal connector**: Watch for server type detection and sync strategy selection
- **Both**: Look for "Processed X changes" messages during active sync periods
- **Normal behavior**: Empty sync cycles (no changes) are expected during quiet periods

The service is designed to run continuously and recover from temporary network or database issues.

## Choosing the Right Connector

### Use AD-Optimized Connector When:
- ✅ You have **only Active Directory** environments
- ✅ You need **maximum performance** for AD synchronization
- ✅ You want **DirSync cookie optimization** for large AD deployments
- ✅ You need **deleted user tracking** from AD Recycle Bin

### Use Universal Connector When:
- ✅ You have **mixed LDAP environments** (AD + OpenLDAP + 389DS)
- ✅ You need **OpenLDAP or 389DS support**
- ✅ You want **automatic server type detection**
- ✅ You're building a **multi-tenant system** with different LDAP servers
- ✅ You prefer a **single codebase** for all LDAP types

### Migration Path
The universal connector is fully compatible with the same database schema, making migration straightforward:
1. Test universal connector with `--dry-run` mode
2. Switch to universal connector: `./start.sh --universal`
3. Both connectors can coexist (use different compose profiles)
