#!/usr/bin/env python3

"""
Keycloak LDAP Configuration Script
Configures LDAP/Active Directory integration with Keycloak
"""

import os
import sys
import requests
from typing import Dict, Any

# Configuration from environment or defaults
KC_SERVER = os.getenv('KC_SERVER', 'http://auth.localhost:8080')
KC_ADMIN_USER = os.getenv('KC_ADMIN_USER', 'admin')
KC_ADMIN_PASS = os.getenv('KC_ADMIN_PASS', 'admin')
REALM_NAME = os.getenv('REALM_NAME', 'cybercore')


class KeycloakLDAPConfig:
    def __init__(self, server_url: str, admin_user: str, admin_pass: str, realm: str):
        self.server_url = server_url
        self.admin_user = admin_user
        self.admin_pass = admin_pass
        self.realm = realm
        self.access_token = None
        
    def get_admin_token(self) -> str:
        """Get admin access token"""
        url = f"{self.server_url}/realms/master/protocol/openid-connect/token"
        data = {
            'username': self.admin_user,
            'password': self.admin_pass,
            'grant_type': 'password',
            'client_id': 'admin-cli'
        }
        
        response = requests.post(url, data=data)
        response.raise_for_status()
        
        self.access_token = response.json()['access_token']
        return self.access_token
    
    def configure_active_directory(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Configure Active Directory integration"""
        
        ldap_config = {
            "name": config.get('name', 'Active Directory'),
            "providerId": "ldap",
            "providerType": "org.keycloak.storage.UserStorageProvider",
            "parentId": self.realm,
            "config": {
                # Connection settings
                "vendor": ["ad"],
                "connectionUrl": [config.get('url', 'ldaps://ad.example.com:636')],
                "bindDn": [config.get('bind_dn', 'CN=Service Account,OU=Service Accounts,DC=example,DC=com')],
                "bindCredential": [config.get('bind_password', '')],
                "startTls": ["false"],
                "useTruststoreSpi": ["ldapsOnly"],
                
                # User settings
                "usersDn": [config.get('users_dn', 'DC=example,DC=com')],
                "usernameLDAPAttribute": ["sAMAccountName"],
                "rdnLDAPAttribute": ["cn"],
                "uuidLDAPAttribute": ["objectGUID"],
                "userObjectClasses": ["person, organizationalPerson, user"],
                "customUserSearchFilter": [config.get('user_filter', '')],
                
                # Synchronization settings
                "searchScope": ["2"],  # Subtree
                "pagination": ["true"],
                "batchSizeForSync": ["1000"],
                "fullSyncPeriod": [str(config.get('full_sync_period', 604800))],  # Weekly
                "changedSyncPeriod": [str(config.get('changed_sync_period', 86400))],  # Daily
                
                # Import settings
                "importEnabled": ["true"],
                "syncRegistrations": ["false"],
                "editMode": [config.get('edit_mode', 'READ_ONLY')],
                
                # Authentication settings
                "authType": ["simple"],
                "allowKerberosAuthentication": [str(config.get('kerberos', False)).lower()],
                "useKerberosForPasswordAuthentication": [str(config.get('kerberos_password', False)).lower()],
                
                # Other settings
                "trustEmail": ["true"],
                "debug": ["false"],
                "cachePolicy": ["DEFAULT"]
            }
        }
        
        # Add mapper configurations
        mappers = self._get_ad_mappers()
        
        return self._create_ldap_provider(ldap_config, mappers)
    
    def configure_openldap(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Configure OpenLDAP integration"""
        
        ldap_config = {
            "name": config.get('name', 'OpenLDAP'),
            "providerId": "ldap",
            "providerType": "org.keycloak.storage.UserStorageProvider",
            "parentId": self.realm,
            "config": {
                # Connection settings
                "vendor": ["other"],
                "connectionUrl": [config.get('url', 'ldap://openldap.example.com:389')],
                "bindDn": [config.get('bind_dn', 'cn=admin,dc=example,dc=com')],
                "bindCredential": [config.get('bind_password', '')],
                "startTls": [str(config.get('start_tls', False)).lower()],
                
                # User settings
                "usersDn": [config.get('users_dn', 'ou=users,dc=example,dc=com')],
                "usernameLDAPAttribute": ["uid"],
                "rdnLDAPAttribute": ["uid"],
                "uuidLDAPAttribute": ["entryUUID"],
                "userObjectClasses": ["inetOrgPerson, organizationalPerson"],
                "customUserSearchFilter": [config.get('user_filter', '')],
                
                # Synchronization settings
                "searchScope": ["2"],  # Subtree
                "pagination": ["true"],
                "batchSizeForSync": ["1000"],
                "fullSyncPeriod": [str(config.get('full_sync_period', 604800))],
                "changedSyncPeriod": [str(config.get('changed_sync_period', 86400))],
                
                # Import settings
                "importEnabled": ["true"],
                "syncRegistrations": ["false"],
                "editMode": [config.get('edit_mode', 'READ_ONLY')],
                
                # Authentication settings
                "authType": ["simple"],
                
                # Other settings
                "trustEmail": ["true"],
                "debug": ["false"],
                "cachePolicy": ["DEFAULT"]
            }
        }
        
        # Add mapper configurations
        mappers = self._get_openldap_mappers()
        
        return self._create_ldap_provider(ldap_config, mappers)
    
    def _create_ldap_provider(self, config: Dict[str, Any], mappers: list) -> Dict[str, Any]:
        """Create LDAP provider in Keycloak"""
        
        if not self.access_token:
            self.get_admin_token()
        
        headers = {
            'Authorization': f'Bearer {self.access_token}',
            'Content-Type': 'application/json'
        }
        
        # Create the LDAP provider
        url = f"{self.server_url}/admin/realms/{self.realm}/components"
        response = requests.post(url, headers=headers, json=config)
        
        if response.status_code == 201:
            print(f"✓ LDAP provider '{config['name']}' created successfully")
            
            # Get the provider ID from the response
            location = response.headers.get('Location', '')
            provider_id = location.split('/')[-1] if location else None
            
            if provider_id:
                # Create mappers
                for mapper in mappers:
                    mapper['parentId'] = provider_id
                    mapper_response = requests.post(url, headers=headers, json=mapper)
                    if mapper_response.status_code == 201:
                        print(f"  ✓ Mapper '{mapper['name']}' created")
                    else:
                        print(f"  ✗ Failed to create mapper '{mapper['name']}': {mapper_response.status_code}")
                
                # Trigger initial sync
                self._sync_users(provider_id)
                
            return {'success': True, 'provider_id': provider_id}
        else:
            print(f"✗ Failed to create LDAP provider: {response.status_code}")
            print(f"Response: {response.text}")
            return {'success': False, 'error': response.text}
    
    def _get_ad_mappers(self) -> list:
        """Get Active Directory attribute mappers"""
        return [
            {
                "name": "username",
                "providerId": "user-attribute-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "ldap.attribute": ["sAMAccountName"],
                    "is.mandatory.in.ldap": ["true"],
                    "always.read.value.from.ldap": ["false"],
                    "read.only": ["true"],
                    "user.model.attribute": ["username"]
                }
            },
            {
                "name": "email",
                "providerId": "user-attribute-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "ldap.attribute": ["mail"],
                    "is.mandatory.in.ldap": ["false"],
                    "always.read.value.from.ldap": ["false"],
                    "read.only": ["true"],
                    "user.model.attribute": ["email"]
                }
            },
            {
                "name": "first name",
                "providerId": "user-attribute-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "ldap.attribute": ["givenName"],
                    "is.mandatory.in.ldap": ["false"],
                    "always.read.value.from.ldap": ["true"],
                    "read.only": ["true"],
                    "user.model.attribute": ["firstName"]
                }
            },
            {
                "name": "last name",
                "providerId": "user-attribute-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "ldap.attribute": ["sn"],
                    "is.mandatory.in.ldap": ["false"],
                    "always.read.value.from.ldap": ["true"],
                    "read.only": ["true"],
                    "user.model.attribute": ["lastName"]
                }
            },
            {
                "name": "groups",
                "providerId": "group-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "groups.dn": ["OU=Groups,DC=example,DC=com"],
                    "group.name.ldap.attribute": ["cn"],
                    "group.object.classes": ["group"],
                    "preserve.group.inheritance": ["true"],
                    "membership.ldap.attribute": ["member"],
                    "membership.attribute.type": ["DN"],
                    "groups.ldap.filter": [],
                    "mode": ["READ_ONLY"],
                    "user.roles.retrieve.strategy": ["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"],
                    "memberof.ldap.attribute": ["memberOf"],
                    "drop.non.existing.groups.during.sync": ["false"]
                }
            }
        ]
    
    def _get_openldap_mappers(self) -> list:
        """Get OpenLDAP attribute mappers"""
        return [
            {
                "name": "username",
                "providerId": "user-attribute-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "ldap.attribute": ["uid"],
                    "is.mandatory.in.ldap": ["true"],
                    "always.read.value.from.ldap": ["false"],
                    "read.only": ["true"],
                    "user.model.attribute": ["username"]
                }
            },
            {
                "name": "email",
                "providerId": "user-attribute-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "ldap.attribute": ["mail"],
                    "is.mandatory.in.ldap": ["false"],
                    "always.read.value.from.ldap": ["false"],
                    "read.only": ["true"],
                    "user.model.attribute": ["email"]
                }
            },
            {
                "name": "first name",
                "providerId": "user-attribute-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "ldap.attribute": ["givenName"],
                    "is.mandatory.in.ldap": ["false"],
                    "always.read.value.from.ldap": ["true"],
                    "read.only": ["true"],
                    "user.model.attribute": ["firstName"]
                }
            },
            {
                "name": "last name",
                "providerId": "user-attribute-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "ldap.attribute": ["sn"],
                    "is.mandatory.in.ldap": ["false"],
                    "always.read.value.from.ldap": ["true"],
                    "read.only": ["true"],
                    "user.model.attribute": ["lastName"]
                }
            },
            {
                "name": "groups",
                "providerId": "group-ldap-mapper",
                "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
                "config": {
                    "groups.dn": ["ou=groups,dc=example,dc=com"],
                    "group.name.ldap.attribute": ["cn"],
                    "group.object.classes": ["groupOfNames"],
                    "preserve.group.inheritance": ["true"],
                    "membership.ldap.attribute": ["member"],
                    "membership.attribute.type": ["DN"],
                    "groups.ldap.filter": [],
                    "mode": ["READ_ONLY"],
                    "user.roles.retrieve.strategy": ["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"],
                    "drop.non.existing.groups.during.sync": ["false"]
                }
            }
        ]
    
    def _sync_users(self, provider_id: str):
        """Trigger user synchronization"""
        if not self.access_token:
            self.get_admin_token()
        
        headers = {
            'Authorization': f'Bearer {self.access_token}'
        }
        
        # Trigger full sync
        url = f"{self.server_url}/admin/realms/{self.realm}/user-storage/{provider_id}/sync"
        response = requests.post(url, headers=headers, params={'action': 'triggerFullSync'})
        
        if response.status_code == 200:
            result = response.json()
            print(f"✓ User sync triggered: {result}")
        else:
            print(f"✗ Failed to trigger user sync: {response.status_code}")
    
    def test_ldap_connection(self, provider_id: str) -> bool:
        """Test LDAP connection"""
        if not self.access_token:
            self.get_admin_token()
        
        headers = {
            'Authorization': f'Bearer {self.access_token}'
        }
        
        url = f"{self.server_url}/admin/realms/{self.realm}/testLDAPConnection"
        response = requests.post(url, headers=headers, json={'componentId': provider_id})
        
        if response.status_code == 204:
            print("✓ LDAP connection test successful")
            return True
        else:
            print(f"✗ LDAP connection test failed: {response.status_code}")
            return False


def main():
    """Main function to configure LDAP"""
    
    print("=== Keycloak LDAP Configuration ===")
    print(f"Server: {KC_SERVER}")
    print(f"Realm: {REALM_NAME}")
    print()
    
    # Initialize client
    client = KeycloakLDAPConfig(KC_SERVER, KC_ADMIN_USER, KC_ADMIN_PASS, REALM_NAME)
    
    # Get admin token
    try:
        client.get_admin_token()
        print("✓ Successfully authenticated as admin")
    except Exception as e:
        print(f"✗ Failed to authenticate: {e}")
        sys.exit(1)
    
    # Select LDAP type
    print("\nSelect LDAP type to configure:")
    print("1. Active Directory")
    print("2. OpenLDAP")
    print("3. Skip LDAP configuration")
    
    choice = input("\nEnter choice (1-3): ").strip()
    
    if choice == "1":
        # Configure Active Directory
        print("\n--- Active Directory Configuration ---")
        config = {
            'name': input("Provider name [Active Directory]: ").strip() or "Active Directory",
            'url': input("LDAP URL [ldaps://ad.example.com:636]: ").strip() or "ldaps://ad.example.com:636",
            'bind_dn': input("Bind DN: ").strip(),
            'bind_password': input("Bind Password: ").strip(),
            'users_dn': input("Users DN [DC=example,DC=com]: ").strip() or "DC=example,DC=com",
            'user_filter': input("User filter (optional): ").strip(),
            'kerberos': input("Enable Kerberos (y/n) [n]: ").strip().lower() == 'y',
            'edit_mode': 'READ_ONLY'
        }
        
        if config['bind_dn'] and config['bind_password']:
            result = client.configure_active_directory(config)
            if result['success']:
                print("\n✓ Active Directory configuration complete!")
        else:
            print("✗ Bind DN and password are required")
    
    elif choice == "2":
        # Configure OpenLDAP
        print("\n--- OpenLDAP Configuration ---")
        config = {
            'name': input("Provider name [OpenLDAP]: ").strip() or "OpenLDAP",
            'url': input("LDAP URL [ldap://openldap.example.com:389]: ").strip() or "ldap://openldap.example.com:389",
            'bind_dn': input("Bind DN: ").strip(),
            'bind_password': input("Bind Password: ").strip(),
            'users_dn': input("Users DN [ou=users,dc=example,dc=com]: ").strip() or "ou=users,dc=example,dc=com",
            'user_filter': input("User filter (optional): ").strip(),
            'start_tls': input("Enable StartTLS (y/n) [n]: ").strip().lower() == 'y',
            'edit_mode': 'READ_ONLY'
        }
        
        if config['bind_dn'] and config['bind_password']:
            result = client.configure_openldap(config)
            if result['success']:
                print("\n✓ OpenLDAP configuration complete!")
        else:
            print("✗ Bind DN and password are required")
    
    elif choice == "3":
        print("Skipping LDAP configuration")
    
    else:
        print("Invalid choice")
    
    print("\n=== Configuration Complete ===")
    print(f"Access Keycloak admin console at: {KC_SERVER}/admin")
    print(f"Realm: {REALM_NAME}")


if __name__ == "__main__":
    main()