-- Core user table (synced from LDAP/Keycloak)
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

-- Group definitions (from LDAP groups or KC groups/roles)
CREATE TABLE IF NOT EXISTS groups (
    id      SERIAL PRIMARY KEY,
    key     TEXT UNIQUE NOT NULL,
    name    TEXT NOT NULL
);

-- User ↔ group mapping
CREATE TABLE IF NOT EXISTS user_groups (
    user_id  INT REFERENCES users(id) ON DELETE CASCADE,
    group_id INT REFERENCES groups(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, group_id)
);

-- Achievements and badges (local to CyberHub)
CREATE TABLE IF NOT EXISTS achievements (
    id          SERIAL PRIMARY KEY,
    key         TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS user_achievements (
    user_id        INT REFERENCES users(id) ON DELETE CASCADE,
    achievement_id INT REFERENCES achievements(id) ON DELETE CASCADE,
    awarded_at     TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, achievement_id)
);