import os, time, logging
import psycopg2
from ldap3 import Server, Connection, ALL, NTLM, SIMPLE, SUBTREE

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                    format="%(asctime)s - %(levelname)s - %(message)s")

# ---- Env ----
# Check for dry_run mode first
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

# LDAP configuration (only required in non-dry_run mode)
if not DRY_RUN:
    LDAP_URI = os.getenv("LDAP_URI")
    BASE_DN  = os.getenv("LDAP_BASE_DN")
    BIND_DN  = os.getenv("LDAP_BIND_DN")
    BIND_PW  = os.getenv("LDAP_BIND_PW")
    
    if not all([LDAP_URI, BASE_DN, BIND_DN, BIND_PW]):
        raise ValueError("Required LDAP envs: LDAP_URI, LDAP_BASE_DN, LDAP_BIND_DN, LDAP_BIND_PW")
else:
    # dry_run mode - LDAP settings not required
    LDAP_URI = None
    BASE_DN = None
    BIND_DN = None
    BIND_PW = None

PG = dict(
    host=os.getenv("DB_HOST", "localhost"),
    port=int(os.getenv("DB_PORT", "5432")),
    dbname=os.getenv("DB_NAME"),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASS"),
)
if not all([PG["dbname"], PG["user"], PG["password"]]):
    raise ValueError("Required DB envs: DB_NAME, DB_USER, DB_PASS")

INTERVAL        = int(os.getenv("INTERVAL", "30"))
PAGE_SIZE       = int(os.getenv("DIRSYNC_PAGE_SIZE", "2000"))
INCLUDE_DELETES = os.getenv("INCLUDE_DELETES", "false").lower() == "true"
COOKIE_FILE     = os.getenv("DIRSYNC_COOKIE_FILE", "/app/cookies/.dirsync_cookie")

# ---- AD controls ----
DIRSYNC_OID      = "1.2.840.113556.1.4.841" # Test OID
SHOW_DELETED_OID = "1.2.840.113556.1.4.417" # Test OID

# ---- Helpers ----
def _first(v):
    """ldap3 sometimes returns scalar or list; normalize to first value or None."""
    if v is None:
        return None
    if isinstance(v, (list, tuple)):
        return v[0] if v else None
    return v

def load_cookie() -> bytes:
    try:
        with open(COOKIE_FILE, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return b""

def save_cookie(cookie: bytes):
    with open(COOKIE_FILE, "wb") as f:
        f.write(cookie or b"")

def determine_user_status(user_data):
    """
    Determine user status based on LDAP attributes.
    Returns: 'active', 'inactive', 'suspended', 'banned', or 'deleted'
    """
    # Check if user is deleted in AD
    if user_data.get("isDeleted", False):
        return 'deleted'
    
    # Get userAccountControl flags
    uac = user_data.get("userAccountControl")
    if uac:
        uac_value = int(uac)
        
        # Check if account is disabled (UF_ACCOUNTDISABLE = 2)
        if uac_value & 2:
            return 'inactive'
        
        # Check if account is locked out (UF_LOCKOUT = 16) 
        if uac_value & 16:
            return 'suspended'
            
        # Check if password never expires but account is marked as requiring password change
        # This could indicate a banned/restricted account
        if (uac_value & 65536) and (uac_value & 8388608):  # UF_DONT_EXPIRE_PASSWD + UF_PASSWORD_EXPIRED
            return 'banned'
    
    # Check account expiration
    account_expires = user_data.get("accountExpires")
    if account_expires and account_expires != "0" and account_expires != "9223372036854775807":  # Not never expires
        # Convert from Windows FILETIME (100ns intervals since 1601-01-01) to Unix timestamp
        try:
            import datetime
            # Windows FILETIME epoch starts at 1601-01-01, Unix at 1970-01-01
            filetime_epoch_diff = 11644473600  # seconds between 1601 and 1970
            timestamp = (int(account_expires) / 10000000) - filetime_epoch_diff
            expiry_date = datetime.datetime.fromtimestamp(timestamp)
            
            if expiry_date < datetime.datetime.now():
                return 'inactive'  # Account expired
        except (ValueError, OverflowError):
            pass  # Invalid date, ignore
    
    # Check lockout time (if currently locked out)
    lockout_time = user_data.get("lockoutTime")
    if lockout_time and lockout_time != "0":
        return 'suspended'
    
    # Default to active if no negative indicators
    return 'active'

def generate_dry_run_users(iteration_count):
    """
    Generate dry_run LDAP user data for testing without actual AD server.
    Simulates different user scenarios and status changes over time.
    """
    import random
    import time
    
    # Base users that always exist
    base_users = [
        {
            "dn": "CN=Alice Johnson,OU=Users,DC=example,DC=org",
            "sAMAccountName": "ajohnson",
            "mail": "alice.johnson@example.org",
            "givenName": "Alice", 
            "sn": "Johnson",
            "cn": "Alice Johnson",
            "userAccountControl": "512",  # Normal account
        },
        {
            "dn": "CN=Bob Smith,OU=Users,DC=example,DC=org",
            "sAMAccountName": "bsmith",
            "mail": "bob.smith@example.org",
            "givenName": "Bob",
            "sn": "Smith", 
            "cn": "Bob Smith",
            "userAccountControl": "514" if iteration_count > 3 else "512",  # Gets disabled after iteration 3
        },
        {
            "dn": "CN=Carol Williams,OU=Users,DC=example,DC=org",
            "sAMAccountName": "cwilliams",
            "mail": "carol.williams@example.org",
            "givenName": "Carol",
            "sn": "Williams",
            "cn": "Carol Williams", 
            "userAccountControl": "528",  # Locked account
            "lockoutTime": "132844567890123456",
        },
    ]
    
    # Add some variation based on iteration to simulate changes
    if iteration_count > 5:
        # Add a new user after 5 iterations
        base_users.append({
            "dn": "CN=David Brown,OU=Users,DC=example,DC=org",
            "sAMAccountName": "dbrown",
            "mail": "david.brown@example.org", 
            "givenName": "David",
            "sn": "Brown",
            "cn": "David Brown",
            "userAccountControl": "512",
        })
    
    if iteration_count > 8:
        # Mark Alice as deleted after 8 iterations (if INCLUDE_DELETES is true)
        if INCLUDE_DELETES:
            # Create a new dict for the deleted user to avoid type issues
            deleted_alice = base_users[0].copy()
            deleted_alice["isDeleted"] = "TRUE"
            base_users[0] = deleted_alice
            
    # Simulate only returning changes (like real DirSync would)
    if iteration_count == 1:
        # First run - return all users
        return base_users
    elif iteration_count == 4:
        # Return Bob with disabled status
        return [user for user in base_users if user["sAMAccountName"] == "bsmith"]
    elif iteration_count == 6:
        # Return the new user David
        return [user for user in base_users if user["sAMAccountName"] == "dbrown"]
    elif iteration_count == 9 and INCLUDE_DELETES:
        # Return deleted Alice
        return [user for user in base_users if user["sAMAccountName"] == "ajohnson"]
    else:
        # No changes - return empty list (delta sync)
        return []

def dry_run_ldap_search(iteration_count):
    """
    dry_run LDAP search that simulates DirSync responses without actual AD server.
    """
    users = generate_dry_run_users(iteration_count)
    
    # Convert to LDAP response format
    dry_run_response = []
    for user in users:
        # Convert user dict to LDAP entry format
        attributes = {}
        for key, value in user.items():
            if key != "dn":
                attributes[key] = [value] if value is not None else []
        
        entry = {
            "type": "searchResEntry",
            "dn": user["dn"],
            "attributes": attributes
        }
        dry_run_response.append(entry)
    
    # dry_run controls response with fake cookie
    dry_run_controls = {
        "1.2.840.113556.1.4.841": {
            "type": "1.2.840.113556.1.4.841",
            "value": {
                "cookie": f"dry_run_cookie_{iteration_count}_{int(time.time())}".encode()
            }
        }
    }
    
    return dry_run_response, {"controls": dry_run_controls}

# Enhanced upsert with status tracking
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

def upsert_user(cur, user, status: str):
    """
    Upsert user with enhanced status tracking.
    status should be one of: 'active', 'inactive', 'suspended', 'banned', 'deleted'
    """
    # Determine if user should be considered "active" for backward compatibility
    active = status == 'active'
    
    cur.execute(
        UPSERT_SQL,
        (
            user.get("sAMAccountName"),
            user.get("mail"),
            user.get("givenName"),
            user.get("sn"),
            user.get("cn") or " ".join(x for x in [user.get("givenName"), user.get("sn")] if x),
            user["dn"],
            bool(active),
            status,
            status,  # used by the CASE in VALUES for deleted_at
        ),
    )

def establish_ldap_connection():
    """
    Establish LDAP connection with retry logic.
    Returns connection object or None if failed.
    """
    if DRY_RUN:
        return None
        
    try:
        # Real LDAP mode - validate environment variables
        assert LDAP_URI is not None
        assert BASE_DN is not None
        assert BIND_DN is not None
        assert BIND_PW is not None

        # LDAP bind
        auth_method = NTLM if "\\" in BIND_DN else SIMPLE
        use_ssl = LDAP_URI.lower().startswith("ldaps")
        server = Server(LDAP_URI, get_info=ALL, use_ssl=use_ssl)
        conn = Connection(server, user=BIND_DN, password=BIND_PW, authentication=auth_method, auto_bind=True)
        logging.info("LDAP bind OK")
        return conn
    except Exception as e:
        logging.error(f"Failed to establish LDAP connection: {e}")
        return None

def main():
    logging.info("Starting DirSync...")
    logging.info(f"LDAP={LDAP_URI} BASE_DN={BASE_DN} interval={INTERVAL}s page_size={PAGE_SIZE} include_deletes={INCLUDE_DELETES}")
    logging.info(f"DRY_RUN={DRY_RUN}")

    if DRY_RUN:
        logging.info("Running in dry_run MODE - no actual LDAP server required")

    # Postgres
    pg = psycopg2.connect(
        host=PG["host"], port=PG["port"],
        database=PG["dbname"], user=PG["user"], password=PG["password"]
    )
    pg.autocommit = True
    cur = pg.cursor()
    logging.info("Postgres connection OK")

    attrs = ["sAMAccountName", "mail", "givenName", "sn", "cn", "isDeleted", 
             "userAccountControl", "accountExpires", "lockoutTime"]
    iteration = 0
    conn = None  # LDAP connection, will be established as needed

    while True:
        try:
            iteration += 1
            logging.debug(f"Sync iteration #{iteration}…")

            cookie = load_cookie()

            if DRY_RUN:
                # Use dry_run data instead of real LDAP
                dry_run_response, dry_run_result = dry_run_ldap_search(iteration)
                ok = True
                processed = 0
                
                for entry in dry_run_response:
                    if entry.get("type") != "searchResEntry":
                        continue

                    a  = entry.get("attributes") or {}
                    dn = entry["dn"]
                    user = {
                        "dn":                  dn,
                        "sAMAccountName":      _first(a.get("sAMAccountName")),
                        "mail":                _first(a.get("mail")),
                        "givenName":           _first(a.get("givenName")),
                        "sn":                  _first(a.get("sn")),
                        "cn":                  _first(a.get("cn")),
                        "isDeleted":           bool(a.get("isDeleted", False)),
                        "userAccountControl":  _first(a.get("userAccountControl")),
                        "accountExpires":      _first(a.get("accountExpires")),
                        "lockoutTime":         _first(a.get("lockoutTime")),
                    }

                    if user["sAMAccountName"]:
                        # Determine user status based on LDAP attributes
                        status = determine_user_status(user)
                        upsert_user(cur, user, status)
                        processed += 1
                        logging.debug(f"User {user['sAMAccountName']} status: {status}")

                # Save dry_run cookie
                cookie_out = dry_run_result.get("controls", {}).get(DIRSYNC_OID, {}).get("value", {}).get("cookie")
                if cookie_out:
                    save_cookie(cookie_out)
            
            else:
                # Real LDAP mode - establish connection if needed
                if BASE_DN is None:
                    logging.error("BASE_DN is not configured, cannot perform LDAP sync")
                    time.sleep(15)
                    continue
                    
                if conn is None:
                    conn = establish_ldap_connection()
                    
                if conn is None:
                    # LDAP connection failed, log error and wait before retrying
                    logging.error("LDAP connection unavailable, skipping sync iteration. Will retry in 15 seconds...")
                    time.sleep(15)
                    continue
                
                # Test if connection is still valid
                try:
                    # Try a simple search to test connection health
                    test_ok = conn.search(
                        search_base=BASE_DN,
                        search_filter="(objectClass=*)",
                        search_scope=SUBTREE,
                        attributes=[],
                        size_limit=1
                    )
                    if not test_ok:
                        logging.warning("LDAP connection test failed, re-establishing connection")
                        conn = establish_ldap_connection()
                        if conn is None:
                            logging.error("Failed to re-establish LDAP connection, skipping sync iteration. Will retry in 15 seconds...")
                            time.sleep(15)
                            continue
                except Exception as e:
                    logging.warning(f"LDAP connection test error: {e}, re-establishing connection")
                    conn = establish_ldap_connection()
                    if conn is None:
                        logging.error("Failed to re-establish LDAP connection, skipping sync iteration. Will retry in 15 seconds...")
                        time.sleep(15)
                        continue
                
                # Build controls list - DirSync is always needed
                controls = [(DIRSYNC_OID, True, (1, PAGE_SIZE, cookie))]  # flags=1, max_bytes, cookie
                search_filter = "(objectClass=user)"
                
                if INCLUDE_DELETES:
                    # Show Deleted control - different format, no value needed
                    from ldap3.extend.microsoft.dirSync import DirSync
                    # Use dict format for mixed control types 
                    controls = {
                        DIRSYNC_OID: (True, (1, PAGE_SIZE, cookie)),
                        SHOW_DELETED_OID: (True, None)
                    }
                    search_filter = "(|(objectClass=user)(isDeleted=TRUE))"

                try:
                    ok = conn.search(
                        search_base=BASE_DN,
                        search_filter=search_filter,
                        search_scope=SUBTREE,
                        attributes=attrs,
                        controls=controls,
                    )
                    if not ok:
                        logging.warning(f"LDAP search failed: result={conn.result}")
                        # Don't reset connection here, might be a transient search issue
                except Exception as e:
                    logging.error(f"LDAP search error: {e}, will re-establish connection next iteration")
                    conn = None  # Mark connection as invalid
                    time.sleep(15)
                    continue

                processed = 0
                try:
                    for entry in conn.response or []:
                        if entry.get("type") != "searchResEntry":
                            continue

                        a  = entry.get("attributes") or {}
                        dn = entry["dn"]
                        user = {
                            "dn":                  dn,
                            "sAMAccountName":      _first(a.get("sAMAccountName")),
                            "mail":                _first(a.get("mail")),
                            "givenName":           _first(a.get("givenName")),
                            "sn":                  _first(a.get("sn")),
                            "cn":                  _first(a.get("cn")),
                            "isDeleted":           bool(a.get("isDeleted", False)),
                            "userAccountControl":  _first(a.get("userAccountControl")),
                            "accountExpires":      _first(a.get("accountExpires")),
                            "lockoutTime":         _first(a.get("lockoutTime")),
                        }

                        if user["sAMAccountName"]:
                            # Determine user status based on LDAP attributes
                            status = determine_user_status(user)
                            upsert_user(cur, user, status)
                            processed += 1
                            logging.debug(f"User {user['sAMAccountName']} status: {status}")
                except Exception as e:
                    logging.error(f"Error processing LDAP response: {e}")
                    conn = None  # Mark connection as invalid
                    time.sleep(15)
                    continue

                # Save new cookie from response
                cookie_out = None
                try:
                    for ctrl in (conn.result or {}).get("controls", {}).values():
                        ctype = ctrl.get("type") or ctrl.get("controlType")
                        if ctype == DIRSYNC_OID:
                            val = ctrl.get("value", {}) or {}
                            cookie_out = val.get("cookie")
                            break
                    if cookie_out is not None:
                        save_cookie(cookie_out)
                except Exception as e:
                    logging.error(f"Error saving cookie: {e}")
                    # Don't invalidate connection for cookie errors

            if processed:
                logging.info(f"Processed {processed} changes; cookie_len={len(cookie_out or b'')} bytes")
            else:
                logging.debug("No changes this interval")

        except psycopg2.Error as e:
            logging.error(f"Database error in iteration #{iteration}: {e}")
        except Exception as e:
            logging.exception(f"DirSync iteration #{iteration} error: {e}")

        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()