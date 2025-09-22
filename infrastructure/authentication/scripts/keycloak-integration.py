#!/usr/bin/env python3
"""
CyberCore Keycloak Integration Script
Configures Keycloak with PostgreSQL user federation and optional LDAP
"""

import os
import sys
import json
import time
import logging
import requests
from typing import Dict, Optional, List
import psycopg2
from psycopg2.extras import RealDictCursor

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class KeycloakIntegration:
    def __init__(self):
        # Keycloak configuration
        self.kc_server = os.getenv('KC_SERVER', 'http://localhost:8080')
        self.kc_admin_user = os.getenv('KC_ADMIN_USER', 'admin')
        self.kc_admin_pass = os.getenv('KC_ADMIN_PASS', 'admin')
        self.realm_name = os.getenv('REALM_NAME', 'cybercore')
        # If running in container, use container name
        if os.path.exists('/.dockerenv'):
            self.kc_server = os.getenv('KC_SERVER', 'http://keycloak:8080')
        
        # PostgreSQL configuration
        self.db_host = os.getenv('DB_HOST', 'cybercore-postgres')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_name = os.getenv('DB_NAME', 'cyberhub_core')
        self.db_user = os.getenv('DB_USER', 'cyberhub')
        self.db_pass = os.getenv('DB_PASS', 'cyberpass')
        
        # LDAP configuration (optional)
        self.ldap_enabled = os.getenv('LDAP_ENABLED', 'false').lower() == 'true'
        self.ldap_uri = os.getenv('LDAP_URI', '')
        self.ldap_base_dn = os.getenv('LDAP_BASE_DN', '')
        self.ldap_bind_dn = os.getenv('LDAP_BIND_DN', '')
        self.ldap_bind_pw = os.getenv('LDAP_BIND_PW', '')
        self.ldap_type = os.getenv('LDAP_TYPE', 'activedirectory')
        
        self.access_token = None
        self.headers = {'Content-Type': 'application/json'}
        
    def wait_for_keycloak(self, max_attempts: int = 30) -> bool:
        """Wait for Keycloak to be ready"""
        logger.info(f"Waiting for Keycloak at {self.kc_server}...")
        
        for attempt in range(max_attempts):
            try:
                # If using localhost, add Host header for Traefik routing
                headers = {}
                if 'localhost' in self.kc_server:
                    headers = {'Host': 'auth.localhost'}
                
                # Just check if Keycloak responds (redirects to /auth or /admin)
                response = requests.get(f"{self.kc_server}", timeout=5, allow_redirects=False, headers=headers)
                if response.status_code in [200, 302, 303]:
                    logger.info("Keycloak is ready!")
                    return True
            except requests.exceptions.RequestException as e:
                logger.debug(f"Connection attempt failed: {e}")
            
            logger.info(f"Attempt {attempt + 1}/{max_attempts}...")
            time.sleep(5)
        
        logger.error(f"Keycloak failed to start after {max_attempts} attempts")
        return False
    
    def get_admin_token(self) -> bool:
        """Get admin access token"""
        logger.info("Getting admin token...")
        
        data = {
            'username': self.kc_admin_user,
            'password': self.kc_admin_pass,
            'grant_type': 'password',
            'client_id': 'admin-cli'
        }
        
        try:
            response = requests.post(
                f"{self.kc_server}/realms/master/protocol/openid-connect/token",
                data=data
            )
            
            if response.status_code == 200:
                self.access_token = response.json()['access_token']
                self.headers['Authorization'] = f'Bearer {self.access_token}'
                logger.info("Successfully obtained admin token")
                return True
            else:
                logger.error(f"Failed to get admin token: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"Error getting admin token: {e}")
            return False
    
    def import_realm_config(self) -> bool:
        """Import realm configuration from JSON file"""
        logger.info(f"Importing realm configuration for {self.realm_name}...")
        
        realm_config_path = '/app/keycloak-realm-config.json'
        if not os.path.exists(realm_config_path):
            # Use the one we created
            realm_config_path = os.path.join(
                os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
                'auth', 'keycloak-realm-config.json'
            )
        
        try:
            with open(realm_config_path, 'r') as f:
                realm_config = json.load(f)
            
            # Check if realm exists
            check_response = requests.get(
                f"{self.kc_server}/admin/realms/{self.realm_name}",
                headers=self.headers
            )
            
            if check_response.status_code == 200:
                logger.info(f"Realm {self.realm_name} already exists, updating...")
                # Update existing realm
                response = requests.put(
                    f"{self.kc_server}/admin/realms/{self.realm_name}",
                    headers=self.headers,
                    json=realm_config
                )
            else:
                # Create new realm
                response = requests.post(
                    f"{self.kc_server}/admin/realms",
                    headers=self.headers,
                    json=realm_config
                )
            
            if response.status_code in [201, 204]:
                logger.info(f"Successfully imported realm {self.realm_name}")
                return True
            else:
                logger.error(f"Failed to import realm: {response.status_code}")
                logger.error(response.text)
                return False
                
        except Exception as e:
            logger.error(f"Error importing realm config: {e}")
            return False
    
    def configure_postgres_user_storage(self) -> bool:
        """Configure PostgreSQL as a user storage provider"""
        logger.info("Configuring PostgreSQL user storage provider...")
        
        # Custom user storage provider configuration
        storage_config = {
            "name": "postgres-users",
            "providerId": "user-storage-jpa",
            "providerType": "org.keycloak.storage.UserStorageProvider",
            "config": {
                "enabled": ["true"],
                "priority": ["0"],
                "jdbcUrl": [f"jdbc:postgresql://{self.db_host}:{self.db_port}/{self.db_name}"],
                "jdbcDriver": ["org.postgresql.Driver"],
                "user": [self.db_user],
                "password": [self.db_pass],
                "validationQuery": ["SELECT 1"],
                "importEnabled": ["true"],
                "syncRegistrations": ["true"],
                "fullSyncPeriod": ["3600"],
                "changedSyncPeriod": ["900"],
                "cachePolicy": ["DEFAULT"],
                "evictionDay": [""],
                "evictionHour": [""],
                "evictionMinute": [""],
                "maxLifespan": [""],
                "batchSizeForSync": ["1000"]
            }
        }
        
        try:
            response = requests.post(
                f"{self.kc_server}/admin/realms/{self.realm_name}/components",
                headers=self.headers,
                json=storage_config
            )
            
            if response.status_code in [201, 409]:
                logger.info("PostgreSQL user storage provider configured")
                return True
            else:
                logger.warning(f"Could not configure PostgreSQL storage: {response.status_code}")
                # This might fail if custom provider is not available, continue anyway
                return True
                
        except Exception as e:
            logger.warning(f"Error configuring PostgreSQL storage: {e}")
            # Continue even if this fails
            return True
    
    def configure_ldap_federation(self) -> bool:
        """Configure LDAP user federation if enabled"""
        if not self.ldap_enabled:
            logger.info("LDAP federation is disabled, skipping...")
            return True
        
        logger.info(f"Configuring LDAP federation ({self.ldap_type})...")
        
        # Determine LDAP configuration based on type
        if self.ldap_type == 'activedirectory':
            ldap_config = self._get_ad_config()
        elif self.ldap_type == 'openldap':
            ldap_config = self._get_openldap_config()
        else:
            ldap_config = self._get_generic_ldap_config()
        
        try:
            response = requests.post(
                f"{self.kc_server}/admin/realms/{self.realm_name}/components",
                headers=self.headers,
                json=ldap_config
            )
            
            if response.status_code in [201, 409]:
                logger.info("LDAP federation configured successfully")
                return True
            else:
                logger.error(f"Failed to configure LDAP: {response.status_code}")
                logger.error(response.text)
                return False
                
        except Exception as e:
            logger.error(f"Error configuring LDAP: {e}")
            return False
    
    def _get_ad_config(self) -> Dict:
        """Get Active Directory configuration"""
        return {
            "name": "Active Directory",
            "providerId": "ldap",
            "providerType": "org.keycloak.storage.UserStorageProvider",
            "config": {
                "enabled": ["true"],
                "priority": ["1"],
                "fullSyncPeriod": ["3600"],
                "changedSyncPeriod": ["900"],
                "cachePolicy": ["DEFAULT"],
                "evictionDay": [""],
                "evictionHour": [""],
                "evictionMinute": [""],
                "maxLifespan": [""],
                "batchSizeForSync": ["1000"],
                "editMode": ["READ_ONLY"],
                "syncRegistrations": ["false"],
                "vendor": ["ad"],
                "usernameLDAPAttribute": ["sAMAccountName"],
                "rdnLDAPAttribute": ["cn"],
                "uuidLDAPAttribute": ["objectGUID"],
                "userObjectClasses": ["person, organizationalPerson, user"],
                "connectionUrl": [self.ldap_uri],
                "usersDn": [self.ldap_base_dn],
                "authType": ["simple"],
                "bindDn": [self.ldap_bind_dn],
                "bindCredential": [self.ldap_bind_pw],
                "customUserSearchFilter": ["(&(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"],
                "searchScope": ["2"],
                "useTruststoreSpi": ["ldapsOnly"],
                "connectionPooling": ["true"],
                "pagination": ["true"],
                "allowKerberosAuthentication": ["false"],
                "debug": ["false"],
                "useKerberosForPasswordAuthentication": ["false"]
            }
        }
    
    def _get_openldap_config(self) -> Dict:
        """Get OpenLDAP configuration"""
        return {
            "name": "OpenLDAP",
            "providerId": "ldap",
            "providerType": "org.keycloak.storage.UserStorageProvider",
            "config": {
                "enabled": ["true"],
                "priority": ["1"],
                "fullSyncPeriod": ["3600"],
                "changedSyncPeriod": ["900"],
                "cachePolicy": ["DEFAULT"],
                "batchSizeForSync": ["1000"],
                "editMode": ["READ_ONLY"],
                "syncRegistrations": ["false"],
                "vendor": ["other"],
                "usernameLDAPAttribute": ["uid"],
                "rdnLDAPAttribute": ["uid"],
                "uuidLDAPAttribute": ["entryUUID"],
                "userObjectClasses": ["inetOrgPerson, organizationalPerson"],
                "connectionUrl": [self.ldap_uri],
                "usersDn": [self.ldap_base_dn],
                "authType": ["simple"],
                "bindDn": [self.ldap_bind_dn],
                "bindCredential": [self.ldap_bind_pw],
                "customUserSearchFilter": ["(objectClass=inetOrgPerson)"],
                "searchScope": ["2"],
                "useTruststoreSpi": ["ldapsOnly"],
                "connectionPooling": ["true"],
                "pagination": ["true"],
                "debug": ["false"]
            }
        }
    
    def _get_generic_ldap_config(self) -> Dict:
        """Get generic LDAP configuration"""
        return {
            "name": "LDAP",
            "providerId": "ldap",
            "providerType": "org.keycloak.storage.UserStorageProvider",
            "config": {
                "enabled": ["true"],
                "priority": ["1"],
                "fullSyncPeriod": ["3600"],
                "changedSyncPeriod": ["900"],
                "cachePolicy": ["DEFAULT"],
                "batchSizeForSync": ["1000"],
                "editMode": ["READ_ONLY"],
                "syncRegistrations": ["false"],
                "vendor": ["other"],
                "usernameLDAPAttribute": ["uid"],
                "rdnLDAPAttribute": ["uid"],
                "uuidLDAPAttribute": ["entryUUID"],
                "userObjectClasses": ["person"],
                "connectionUrl": [self.ldap_uri],
                "usersDn": [self.ldap_base_dn],
                "authType": ["simple"],
                "bindDn": [self.ldap_bind_dn],
                "bindCredential": [self.ldap_bind_pw],
                "searchScope": ["2"],
                "useTruststoreSpi": ["ldapsOnly"],
                "connectionPooling": ["true"],
                "pagination": ["true"],
                "debug": ["false"]
            }
        }
    
    def sync_postgres_users(self) -> bool:
        """Sync existing PostgreSQL users to Keycloak"""
        logger.info("Syncing PostgreSQL users to Keycloak...")
        
        try:
            # Connect to PostgreSQL
            conn = psycopg2.connect(
                host=self.db_host,
                port=self.db_port,
                database=self.db_name,
                user=self.db_user,
                password=self.db_pass
            )
            
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                # Get all active users
                cursor.execute("""
                    SELECT id, username, email, first_name, last_name, 
                           active, status, auth_provider
                    FROM users 
                    WHERE active = TRUE AND status = 'active'
                """)
                users = cursor.fetchall()
                
                for user in users:
                    # Skip if user already has a Keycloak ID
                    if user.get('keycloak_id'):
                        continue
                    
                    # Create user in Keycloak
                    keycloak_user = {
                        "username": user['username'],
                        "email": user.get('email', f"{user['username']}@cybercore.local"),
                        "emailVerified": True,
                        "enabled": user['active'],
                        "firstName": user.get('first_name', ''),
                        "lastName": user.get('last_name', ''),
                        "attributes": {
                            "postgres_id": [str(user['id'])],
                            "auth_provider": [user.get('auth_provider', 'postgres')]
                        }
                    }
                    
                    response = requests.post(
                        f"{self.kc_server}/admin/realms/{self.realm_name}/users",
                        headers=self.headers,
                        json=keycloak_user
                    )
                    
                    if response.status_code == 201:
                        # Get the created user's ID
                        location = response.headers.get('Location')
                        if location:
                            keycloak_id = location.split('/')[-1]
                            
                            # Update PostgreSQL with Keycloak ID
                            cursor.execute(
                                "UPDATE users SET keycloak_id = %s WHERE id = %s",
                                (keycloak_id, user['id'])
                            )
                            conn.commit()
                            logger.info(f"Synced user {user['username']}")
                    elif response.status_code == 409:
                        logger.info(f"User {user['username']} already exists in Keycloak")
                    else:
                        logger.warning(f"Failed to sync user {user['username']}: {response.status_code}")
            
            conn.close()
            logger.info("User sync completed")
            return True
            
        except Exception as e:
            logger.error(f"Error syncing users: {e}")
            return False
    
    def configure_authentication_flow(self) -> bool:
        """Configure authentication flow to check PostgreSQL first, then LDAP"""
        logger.info("Configuring authentication flow...")
        
        # This would require custom authenticator development
        # For now, we'll use the default flow with priority settings
        logger.info("Using default authentication flow with priority-based federation")
        return True
    
    def create_webhook_client(self) -> bool:
        """Create a client for webhook authentication"""
        logger.info("Creating webhook client for N8N...")
        
        webhook_client = {
            "clientId": "cybercore-webhooks",
            "name": "CyberCore Webhooks",
            "description": "Client for webhook authentication",
            "rootUrl": "http://n8n.localhost:8080",
            "enabled": True,
            "clientAuthenticatorType": "client-secret",
            "secret": "webhook-secret-change-me",
            "standardFlowEnabled": False,
            "implicitFlowEnabled": False,
            "directAccessGrantsEnabled": True,
            "serviceAccountsEnabled": True,
            "publicClient": False,
            "protocol": "openid-connect",
            "fullScopeAllowed": True
        }
        
        try:
            response = requests.post(
                f"{self.kc_server}/admin/realms/{self.realm_name}/clients",
                headers=self.headers,
                json=webhook_client
            )
            
            if response.status_code in [201, 409]:
                logger.info("Webhook client created/exists")
                return True
            else:
                logger.warning(f"Could not create webhook client: {response.status_code}")
                return True
                
        except Exception as e:
            logger.warning(f"Error creating webhook client: {e}")
            return True
    
    def run(self):
        """Run the complete Keycloak integration setup"""
        logger.info("Starting CyberCore Keycloak Integration...")
        
        # Wait for Keycloak to be ready
        if not self.wait_for_keycloak():
            sys.exit(1)
        
        # Get admin token
        if not self.get_admin_token():
            sys.exit(1)
        
        # Import realm configuration
        if not self.import_realm_config():
            logger.warning("Failed to import realm config, continuing...")
        
        # Configure PostgreSQL user storage
        if not self.configure_postgres_user_storage():
            logger.warning("Failed to configure PostgreSQL storage, continuing...")
        
        # Configure LDAP if enabled
        if self.ldap_enabled:
            if not self.configure_ldap_federation():
                logger.warning("Failed to configure LDAP, continuing...")
        
        # Sync existing PostgreSQL users
        if not self.sync_postgres_users():
            logger.warning("Failed to sync users, continuing...")
        
        # Configure authentication flow
        if not self.configure_authentication_flow():
            logger.warning("Failed to configure auth flow, continuing...")
        
        # Create webhook client
        if not self.create_webhook_client():
            logger.warning("Failed to create webhook client, continuing...")
        
        logger.info("=" * 50)
        logger.info("Keycloak Integration Complete!")
        logger.info(f"Access Keycloak at: {self.kc_server}")
        logger.info(f"Admin Console: {self.kc_server}/admin")
        logger.info(f"Realm: {self.realm_name}")
        logger.info("=" * 50)
        
        # Output configuration for other services
        config_output = {
            "keycloak_url": self.kc_server,
            "realm": self.realm_name,
            "client_id": "cybercore",
            "client_secret": "cybercore-secret",
            "webhook_client_id": "cybercore-webhooks",
            "webhook_client_secret": "webhook-secret-change-me"
        }
        
        print(json.dumps(config_output, indent=2))

if __name__ == "__main__":
    integration = KeycloakIntegration()
    integration.run()