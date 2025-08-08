import os, time, logging, datetime
import psycopg2
from ldap3 import Server, Connection, ALL, NTLM, SIMPLE, SUBTREE

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                    format="%(asctime)s - %(levelname)s - %(message)s")

# ---- Environment Variables ----
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

# LDAP Configuration
if not DRY_RUN:
    LDAP_TYPE = os.getenv("LDAP_TYPE", "activedirectory").lower()
    LDAP_URI = os.getenv("LDAP_URI")
    BASE_DN = os.getenv("LDAP_BASE_DN")
    BIND_DN = os.getenv("LDAP_BIND_DN")
    BIND_PW = os.getenv("LDAP_BIND_PW")
    
    if not all([LDAP_URI, BASE_DN, BIND_DN, BIND_PW]):
        raise ValueError("Required LDAP envs: LDAP_URI, LDAP_BASE_DN, LDAP_BIND_DN, LDAP_BIND_PW")
else:
    LDAP_TYPE = "dry_run"
    LDAP_URI = None
    BASE_DN = None
    BIND_DN = None
    BIND_PW = None

# Database Configuration
PG = dict(
    host=os.getenv("DB_HOST", "localhost"),
    port=int(os.getenv("DB_PORT", "5432")),
    dbname=os.getenv("DB_NAME"),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASS"),
)
if not all([PG["dbname"], PG["user"], PG["password"]]):
    raise ValueError("Required DB envs: DB_NAME, DB_USER, DB_PASS")

# Sync Configuration
INTERVAL = int(os.getenv("INTERVAL", "30"))
PAGE_SIZE = int(os.getenv("SYNC_PAGE_SIZE", "2000"))
INCLUDE_DELETES = os.getenv("INCLUDE_DELETES", "false").lower() == "true"

# File Storage
SYNC_STATE_FILE = os.getenv("SYNC_STATE_FILE", "/app/sync_state/.sync_state")
DIRSYNC_COOKIE_FILE = os.getenv("DIRSYNC_COOKIE_FILE", "/app/sync_state/.dirsync_cookie")

# LDAP Server Schemas
LDAP_SCHEMAS = {
    "activedirectory": {
        "user_filter": "(objectClass=user)",
        "deleted_filter": "(|(objectClass=user)(isDeleted=TRUE))",
        "username_attr": "sAMAccountName",
        "attributes": ["sAMAccountName", "mail", "givenName", "sn", "cn", "isDeleted", 
                      "userAccountControl", "accountExpires", "lockoutTime", "modifyTimestamp"],
        "supports_dirsync": True,
        "supports_deleted": True,
        "auth_method": "auto",  # NTLM if domain\user, else SIMPLE
    },
    "openldap": {
        "user_filter": "(objectClass=inetOrgPerson)",
        "deleted_filter": "(objectClass=inetOrgPerson)",  # No deleted object support
        "username_attr": "uid",
        "attributes": ["uid", "mail", "givenName", "sn", "cn", "modifyTimestamp",
                      "shadowExpire", "accountStatus", "pwdAccountLockedTime"],
        "supports_dirsync": False,
        "supports_deleted": False,
        "auth_method": "simple",
    },
    "389ds": {  # 389 Directory Server (Red Hat)
        "user_filter": "(objectClass=person)",
        "deleted_filter": "(objectClass=person)",
        "username_attr": "uid",
        "attributes": ["uid", "mail", "givenName", "sn", "cn", "modifyTimestamp",
                      "nsAccountLock", "passwordExpirationTime"],
        "supports_dirsync": False,
        "supports_deleted": False,
        "auth_method": "simple",
    }
}

# Microsoft DirSync Control OIDs
DIRSYNC_OID = "1.2.840.113556.1.4.841"
SHOW_DELETED_OID = "1.2.840.113556.1.4.417"

# ---- Utility Functions ----
def _first(v):
    """Extract first value from LDAP multi-value attribute"""
    if v is None:
        return None
    if isinstance(v, (list, tuple)):
        return v[0] if v else None
    return v

def load_sync_state():
    """Load synchronization state (timestamp or cookie)"""
    try:
        with open(SYNC_STATE_FILE, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        return None

def save_sync_state(state):
    """Save synchronization state"""
    os.makedirs(os.path.dirname(SYNC_STATE_FILE), exist_ok=True)
    with open(SYNC_STATE_FILE, "w") as f:
        f.write(state or "")

def load_dirsync_cookie():
    """Load DirSync cookie (for AD only)"""
    try:
        with open(DIRSYNC_COOKIE_FILE, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return b""

def save_dirsync_cookie(cookie):
    """Save DirSync cookie (for AD only)"""
    os.makedirs(os.path.dirname(DIRSYNC_COOKIE_FILE), exist_ok=True)
    with open(DIRSYNC_COOKIE_FILE, "wb") as f:
        f.write(cookie or b"")

def detect_ldap_server_type(conn):
    """Auto-detect LDAP server type by examining rootDSE"""
    try:
        conn.search('', '(objectClass=*)', SUBTREE, attributes=['*'])
        if not conn.response:
            return 'unknown'
            
        root_dse = conn.response[0].get('attributes', {})
        
        # Active Directory detection
        if 'defaultNamingContext' in root_dse:
            logging.info("Detected Active Directory server")
            return 'activedirectory'
        
        # 389 Directory Server detection  
        if any('389' in str(v).lower() for v in root_dse.get('vendorName', [])):
            logging.info("Detected 389 Directory Server")
            return '389ds'
            
        # OpenLDAP detection (check for common OpenLDAP attributes)
        if 'configContext' in root_dse or any('openldap' in str(v).lower() for v in root_dse.get('vendorName', [])):
            logging.info("Detected OpenLDAP server")
            return 'openldap'
            
        logging.warning("Unknown LDAP server type, defaulting to OpenLDAP schema")
        return 'openldap'
        
    except Exception as e:
        logging.error(f"Failed to detect LDAP server type: {e}")
        return 'unknown'

def map_user_attributes(entry, schema):
    """Map LDAP entry to standardized user object"""
    attrs = entry.get("attributes", {})
    
    user = {
        "dn": entry["dn"],
        "username": _first(attrs.get(schema["username_attr"])),
        "mail": _first(attrs.get("mail")),
        "givenName": _first(attrs.get("givenName")),
        "sn": _first(attrs.get("sn")),
        "cn": _first(attrs.get("cn")),
        "modifyTimestamp": _first(attrs.get("modifyTimestamp")),
    }
    
    # Add server-specific attributes
    if schema == LDAP_SCHEMAS["activedirectory"]:
        user.update({
            "isDeleted": bool(attrs.get("isDeleted", False)),
            "userAccountControl": _first(attrs.get("userAccountControl")),
            "accountExpires": _first(attrs.get("accountExpires")),
            "lockoutTime": _first(attrs.get("lockoutTime")),
        })
    elif schema == LDAP_SCHEMAS["openldap"]:
        user.update({
            "shadowExpire": _first(attrs.get("shadowExpire")),
            "accountStatus": _first(attrs.get("accountStatus")),
            "pwdAccountLockedTime": _first(attrs.get("pwdAccountLockedTime")),
        })
    elif schema == LDAP_SCHEMAS["389ds"]:
        user.update({
            "nsAccountLock": _first(attrs.get("nsAccountLock")),
            "passwordExpirationTime": _first(attrs.get("passwordExpirationTime")),
        })
    
    return user

def determine_user_status(user_data, ldap_type):
    """Determine user status based on LDAP server type and attributes"""
    
    if ldap_type == "activedirectory":
        return determine_user_status_ad(user_data)
    elif ldap_type == "openldap":
        return determine_user_status_openldap(user_data)
    elif ldap_type == "389ds":
        return determine_user_status_389ds(user_data)
    else:
        return 'active'  # Default fallback

def determine_user_status_ad(user_data):
    """Determine AD user status (existing logic)"""
    if user_data.get("isDeleted", False):
        return 'deleted'
    
    uac = user_data.get("userAccountControl")
    if uac:
        uac_value = int(uac)
        if uac_value & 2:  # UF_ACCOUNTDISABLE
            return 'inactive'
        if uac_value & 16:  # UF_LOCKOUT
            return 'suspended'
        if (uac_value & 65536) and (uac_value & 8388608):  # Complex password restrictions
            return 'banned'
    
    # Check account expiration
    account_expires = user_data.get("accountExpires")
    if account_expires and account_expires not in ["0", "9223372036854775807"]:
        try:
            import datetime
            filetime_epoch_diff = 11644473600
            timestamp = (int(account_expires) / 10000000) - filetime_epoch_diff
            expiry_date = datetime.datetime.fromtimestamp(timestamp)
            if expiry_date < datetime.datetime.now():
                return 'inactive'
        except (ValueError, OverflowError):
            pass
    
    # Check lockout
    lockout_time = user_data.get("lockoutTime")
    if lockout_time and lockout_time != "0":
        return 'suspended'
    
    return 'active'

def determine_user_status_openldap(user_data):
    """Determine OpenLDAP user status"""
    # Check shadowAccount expiration
    shadow_expire = user_data.get("shadowExpire")
    if shadow_expire and shadow_expire != "0":
        try:
            expire_date = datetime.datetime.fromtimestamp(int(shadow_expire) * 86400)
            if expire_date < datetime.datetime.now():
                return 'inactive'
        except (ValueError, TypeError):
            pass
    
    # Check custom account status
    account_status = user_data.get("accountStatus", "").lower()
    if account_status in ['disabled', 'inactive', 'locked']:
        return 'inactive'
    
    # Check password lockout
    pwd_locked = user_data.get("pwdAccountLockedTime")
    if pwd_locked and pwd_locked != "0":
        return 'suspended'
    
    return 'active'

def determine_user_status_389ds(user_data):
    """Determine 389 Directory Server user status"""
    # Check account lock
    ns_locked = user_data.get("nsAccountLock", "").lower()
    if ns_locked == "true":
        return 'inactive'
    
    # Check password expiration
    pwd_exp = user_data.get("passwordExpirationTime")
    if pwd_exp:
        try:
            # Format: YYYYMMDDHHMMSSZ
            exp_time = datetime.datetime.strptime(pwd_exp, "%Y%m%d%H%M%SZ")
            if exp_time < datetime.datetime.utcnow():
                return 'inactive'
        except ValueError:
            pass
    
    return 'active'

# ---- Database Operations ----
UPSERT_SQL = """
INSERT INTO users (username, email, first_name, last_name, full_name, ldap_dn, active, status, last_ldap_sync, deleted_at)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW(),
        CASE WHEN %s = 'deleted' THEN NOW() ELSE NULL END)
ON CONFLICT (username) DO UPDATE SET
  email           = EXCLUDED.email,
  first_name      = EXCLUDED.first_name,
  last_name       = EXCLUDED.last_name,
  full_name       = EXCLUDED.full_name,
  ldap_dn         = EXCLUDED.ldap_dn,
  active          = EXCLUDED.active,
  status          = EXCLUDED.status,
  last_ldap_sync  = NOW(),
  deleted_at      = CASE
                      WHEN EXCLUDED.status = 'deleted' THEN NOW()
                      ELSE NULL
                    END;
"""

def upsert_user(cur, user, status, ldap_type):
    """Insert or update user in database"""
    active = status == 'active'
    
    cur.execute(
        UPSERT_SQL,
        (
            user.get("username"),
            user.get("mail"),
            user.get("givenName"),
            user.get("sn"),
            user.get("cn") or " ".join(x for x in [user.get("givenName"), user.get("sn")] if x),
            user["dn"],
            bool(active),
            status,
            status,  # Used by CASE in VALUES for deleted_at
        ),
    )

# ---- LDAP Connection Management ----
def establish_ldap_connection(ldap_type, schema):
    """Establish LDAP connection with auto-retry logic"""
    if DRY_RUN:
        return None
        
    if not all([LDAP_URI, BIND_DN, BIND_PW]):
        logging.error("Missing required LDAP connection parameters")
        return None
        
    try:
        # Determine authentication method
        if schema["auth_method"] == "auto":
            auth_method = NTLM if "\\" in str(BIND_DN) else SIMPLE
        else:
            auth_method = NTLM if schema["auth_method"] == "ntlm" else SIMPLE
        
        use_ssl = str(LDAP_URI).lower().startswith("ldaps")
        server = Server(str(LDAP_URI), get_info=ALL, use_ssl=use_ssl)
        conn = Connection(server, user=str(BIND_DN), password=str(BIND_PW), 
                         authentication=auth_method, auto_bind=True)
        
        logging.info(f"LDAP connection established ({ldap_type})")
        return conn
        
    except Exception as e:
        logging.error(f"Failed to establish LDAP connection: {e}")
        return None

# ---- Sync Strategies ----
def sync_activedirectory(conn, schema):
    """Sync using Microsoft DirSync control"""
    cookie = load_dirsync_cookie()
    
    # Build DirSync controls
    controls = [(DIRSYNC_OID, True, (1, PAGE_SIZE, cookie))]
    search_filter = schema["user_filter"]
    
    if INCLUDE_DELETES:
        controls = {
            DIRSYNC_OID: (True, (1, PAGE_SIZE, cookie)),
            SHOW_DELETED_OID: (True, None)
        }
        search_filter = schema["deleted_filter"]
    
    try:
        success = conn.search(
            search_base=BASE_DN,
            search_filter=search_filter,
            search_scope=SUBTREE,
            attributes=schema["attributes"],
            controls=controls,
        )
        
        if not success:
            logging.warning(f"DirSync search failed: {conn.result}")
            return []
        
        # Save new DirSync cookie
        cookie_out = None
        for ctrl in (conn.result or {}).get("controls", {}).values():
            ctype = ctrl.get("type") or ctrl.get("controlType")
            if ctype == DIRSYNC_OID:
                cookie_out = ctrl.get("value", {}).get("cookie")
                break
        
        if cookie_out is not None:
            save_dirsync_cookie(cookie_out)
            
        return conn.response or []
        
    except Exception as e:
        logging.error(f"DirSync search error: {e}")
        return []

def sync_generic_ldap(conn, schema, ldap_type):
    """Sync using timestamp-based approach for OpenLDAP/389DS"""
    last_sync = load_sync_state()
    
    # Build time-based filter
    if last_sync and 'modifyTimestamp' in schema["attributes"]:
        # Query for entries modified since last sync
        time_filter = f"(modifyTimestamp>={last_sync})"
        search_filter = f"(&{schema['user_filter']}{time_filter})"
        logging.info(f"Incremental sync since {last_sync}")
    else:
        # Full sync
        search_filter = schema["user_filter"]
        logging.info("Full sync (first run or no timestamp support)")
    
    try:
        success = conn.search(
            search_base=BASE_DN,
            search_filter=search_filter,
            search_scope=SUBTREE,
            attributes=schema["attributes"],
            size_limit=PAGE_SIZE
        )
        
        if not success:
            logging.warning(f"Generic LDAP search failed: {conn.result}")
            return []
        
        # Save current timestamp for next sync
        current_time = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S.0Z")
        save_sync_state(current_time)
        
        return conn.response or []
        
    except Exception as e:
        logging.error(f"Generic LDAP search error: {e}")
        return []

# ---- Dry Run Mode ----
def generate_dry_run_users(iteration_count):
    """Generate mock users for testing"""
    base_users = [
        {
            "dn": "uid=alice,ou=users,dc=example,dc=org",
            "username": "alice",
            "mail": "alice@example.org",
            "givenName": "Alice",
            "sn": "Johnson",
            "cn": "Alice Johnson",
        },
        {
            "dn": "uid=bob,ou=users,dc=example,dc=org", 
            "username": "bob",
            "mail": "bob@example.org",
            "givenName": "Bob",
            "sn": "Smith",
            "cn": "Bob Smith",
        },
        {
            "dn": "uid=carol,ou=users,dc=example,dc=org",
            "username": "carol",
            "mail": "carol@example.org", 
            "givenName": "Carol",
            "sn": "Williams",
            "cn": "Carol Williams",
        },
    ]
    
    # Simulate changes over iterations
    if iteration_count == 1:
        return base_users
    elif iteration_count == 4:
        # Bob gets disabled
        base_users[1]["accountStatus"] = "disabled"
        return [base_users[1]]
    elif iteration_count == 6:
        # Add new user
        return [{
            "dn": "uid=david,ou=users,dc=example,dc=org",
            "username": "david",
            "mail": "david@example.org",
            "givenName": "David", 
            "sn": "Brown",
            "cn": "David Brown",
        }]
    else:
        return []  # No changes

def dry_run_sync(iteration_count):
    """Simulate LDAP sync for testing"""
    users = generate_dry_run_users(iteration_count)
    return users

# ---- Main Function ----
def main():
    logging.info("Starting Universal LDAP Sync...")
    logging.info(f"LDAP_TYPE={LDAP_TYPE} URI={LDAP_URI} BASE_DN={BASE_DN}")
    logging.info(f"DRY_RUN={DRY_RUN} INTERVAL={INTERVAL}s PAGE_SIZE={PAGE_SIZE}")
    
    # Database connection
    pg = psycopg2.connect(
        host=PG["host"], 
        port=PG["port"],
        database=PG["dbname"], 
        user=PG["user"], 
        password=PG["password"]
    )
    pg.autocommit = True
    cur = pg.cursor()
    logging.info("Database connection established")
    
    # Determine LDAP schema
    if DRY_RUN:
        schema = LDAP_SCHEMAS["openldap"]  # Use OpenLDAP for dry run
        detected_type = "dry_run"
    else:
        schema = LDAP_SCHEMAS.get(LDAP_TYPE, LDAP_SCHEMAS["openldap"])
        detected_type = LDAP_TYPE
    
    iteration = 0
    conn = None
    
    while True:
        try:
            iteration += 1
            logging.debug(f"Sync iteration #{iteration}")
            
            if DRY_RUN:
                # Dry run mode
                entries = dry_run_sync(iteration)
                processed = 0
                
                for user_data in entries:
                    if user_data.get("username"):
                        status = determine_user_status(user_data, "openldap")
                        upsert_user(cur, user_data, status, "openldap")
                        processed += 1
                        logging.debug(f"User {user_data['username']} status: {status}")
                
            else:
                # Real LDAP mode
                if BASE_DN is None:
                    logging.error("BASE_DN not configured")
                    time.sleep(15)
                    continue
                
                # Establish connection if needed
                if conn is None:
                    conn = establish_ldap_connection(detected_type, schema)
                
                if conn is None:
                    logging.error("LDAP connection unavailable, retrying in 15 seconds...")
                    time.sleep(15)
                    continue
                
                # Auto-detect server type if not specified
                if LDAP_TYPE == "auto":
                    detected_type = detect_ldap_server_type(conn)
                    schema = LDAP_SCHEMAS.get(detected_type, LDAP_SCHEMAS["openldap"])
                    logging.info(f"Using schema for {detected_type}")
                
                # Perform sync based on server capabilities
                if schema["supports_dirsync"]:
                    entries = sync_activedirectory(conn, schema)
                else:
                    entries = sync_generic_ldap(conn, schema, detected_type)
                
                processed = 0
                for entry in entries:
                    if entry.get("type") != "searchResEntry":
                        continue
                    
                    user_data = map_user_attributes(entry, schema)
                    if user_data.get("username"):
                        status = determine_user_status(user_data, detected_type)
                        upsert_user(cur, user_data, status, detected_type)
                        processed += 1
                        logging.debug(f"User {user_data['username']} status: {status}")
            
            if processed:
                logging.info(f"Processed {processed} user changes")
            else:
                logging.debug("No changes this iteration")
                
        except psycopg2.Error as e:
            logging.error(f"Database error in iteration #{iteration}: {e}")
        except Exception as e:
            logging.exception(f"Sync iteration #{iteration} error: {e}")
            conn = None  # Reset connection on error
            
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
