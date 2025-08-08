#!/bin/bash

# CyberCore User Profiles - Usage Examples
# This file contains common usage patterns for the start and stop scripts

echo "=== CyberCore User Profiles - Usage Examples ==="
echo
echo "✅ DUAL CONNECTOR SUPPORT: Legacy AD + Universal LDAP"
echo

echo "1. DEVELOPMENT/TESTING (Dry-run mode):"
echo "   ./start.sh --dry-run              # Legacy AD connector with mock data"
echo "   ./start.sh --universal --dry-run  # Universal connector with mock data"
echo "   ./start.sh --openldap --dry-run   # OpenLDAP connector with mock data"
echo "   ./start.sh --dry-run --no-detach  # Start in foreground to see logs"
echo "   ./stop.sh                         # Stop services, keep data"
echo

echo "2. PRODUCTION - Active Directory:"
echo "   ./start.sh                        # Legacy AD connector (DirSync optimized)"
echo "   ./start.sh --universal            # Universal connector (compatible mode)"
echo "   ./stop.sh                         # Stop services, keep data"
echo

echo "3. PRODUCTION - OpenLDAP:"
echo "   ./start.sh --openldap             # Universal connector for OpenLDAP"
echo "   ./start.sh --universal --ldap-type openldap  # Same as above"
echo

echo "4. PRODUCTION - 389 Directory Server:"
echo "   ./start.sh --universal --ldap-type 389ds     # 389DS support"
echo

echo "5. AUTO-DETECTION:"
echo "   ./start.sh --universal --ldap-type auto      # Auto-detect LDAP server type"
echo

echo "3. DEBUGGING:"
echo "   ./start.sh --no-detach            # Start in foreground"
echo "   ./start.sh --force-recreate       # Force rebuild containers"
echo

echo "4. COMPLETE CLEANUP:"
echo "   ./stop.sh --remove-volumes        # Stop and DELETE ALL DATA"
echo "   ./stop.sh --remove-network        # Also remove Docker network"
echo

echo "5. MONITORING:"
echo "   docker logs -f cybercore-postgres                    # Database logs"
echo "   docker logs -f cybercore-ldap-sync                   # Legacy AD connector logs"
echo "   docker logs -f cybercore-universal-ldap-sync         # Universal connector logs"
echo "   docker exec -it cybercore-postgres psql -U cyberhub -d cyberhub_core  # Connect to DB"
echo

echo "6. WEB INTERFACE:"
echo "   open http://localhost:8080        # Adminer database web UI"
echo "   # Use: Server=cybercore-postgres, User=cyberhub, Password=cyberpass, Database=cyberhub_core"
echo

echo "=== Connector Comparison ==="
echo "Legacy AD Connector:"
echo "  ✅ Optimized for Active Directory (DirSync control)"
echo "  ✅ Maximum performance for large AD environments"
echo "  ❌ Active Directory only"
echo
echo "Universal Connector:"
echo "  ✅ Supports AD, OpenLDAP, 389DS, auto-detection"
echo "  ✅ Consistent interface across LDAP servers"
echo "  ✅ Future-proof for new LDAP server types"
echo "  ⚠️  AD performance slightly lower (no DirSync optimization yet)"
echo

echo "=== Services Overview ==="
echo "PostgreSQL:    localhost:5432 (cyberhub_core database)"
echo "Adminer:       localhost:8080 (database web interface)"
echo "LDAP Sync:     Background service (user synchronization)"
echo

echo "Run './start.sh --help' or './stop.sh --help' for detailed options."
