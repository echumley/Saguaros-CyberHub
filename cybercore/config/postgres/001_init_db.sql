-- config/postgres/001_core_init.sql
-- Core schema + core seeds (no library/wiki)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- === Users ===
CREATE TABLE IF NOT EXISTS app_user (
  user_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username       TEXT NOT NULL UNIQUE,
  email          TEXT NOT NULL,
  first_name     TEXT,
  last_name      TEXT,
  auth_provider  TEXT NOT NULL DEFAULT 'keycloak' CHECK (auth_provider IN ('local','keycloak')),
  password_hash  TEXT,
  password_alg   TEXT,
  status         TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','suspended','banned','deleted')),
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_auth_at   TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_app_user_email_lower ON app_user (lower(email));

-- === Groups (text key) ===
CREATE TABLE IF NOT EXISTS app_group (
  key         TEXT PRIMARY KEY,            -- 'cyberlabs','crucible','forge','university','library','wiki'
  label       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- === User↔Group bridge ===
CREATE TABLE IF NOT EXISTS user_group (
  user_id   UUID NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  group_key TEXT NOT NULL REFERENCES app_group(key) ON DELETE CASCADE,
  PRIMARY KEY (user_id, group_key)
);

-- === Modules (text key) ===
CREATE TABLE IF NOT EXISTS module (
  key     TEXT PRIMARY KEY,                -- 'cyberlabs','crucible','forge','university','library','wiki'
  name    TEXT NOT NULL,
  active  BOOLEAN NOT NULL DEFAULT TRUE
);

-- === Resources (generic infra objects) ===
CREATE TABLE IF NOT EXISTS resource (
  resource_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type         TEXT NOT NULL CHECK (type IN ('vm','network','dataset','vpn_account')),
  module_key   TEXT REFERENCES module(key),
  name         TEXT NOT NULL,
  provider_ref TEXT,
  metadata     JSONB NOT NULL DEFAULT '{}'::jsonb,
  status       TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available','provisioning','allocated','error','retired')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (module_key, name)
);

-- === Allocations ===
CREATE TABLE IF NOT EXISTS allocation (
  allocation_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_id    UUID NOT NULL REFERENCES resource(resource_id) ON DELETE CASCADE,
  user_id        UUID REFERENCES app_user(user_id) ON DELETE SET NULL,
  group_key      TEXT REFERENCES app_group(key) ON DELETE SET NULL,
  starts_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at        TIMESTAMPTZ,
  purpose        TEXT,
  quota_units    INTEGER,
  metadata       JSONB NOT NULL DEFAULT '{}'::jsonb,
  CHECK (user_id IS NOT NULL OR group_key IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_allocation_user     ON allocation(user_id);
CREATE INDEX IF NOT EXISTS idx_allocation_group    ON allocation(group_key);
CREATE INDEX IF NOT EXISTS idx_allocation_resource ON allocation(resource_id);

-- === Badges / Achievements ===
CREATE TABLE IF NOT EXISTS badge (
  badge_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key         TEXT NOT NULL UNIQUE,        -- e.g., 'member','onboarding_complete'
  name        TEXT NOT NULL,
  description TEXT,
  module_key  TEXT REFERENCES module(key), -- NULL = global badge
  icon_url    TEXT,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_badge (
  user_id    UUID NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  badge_id   UUID NOT NULL REFERENCES badge(badge_id) ON DELETE CASCADE,
  earned_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  awarded_by UUID REFERENCES app_user(user_id),
  metadata   JSONB NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (user_id, badge_id)
);
CREATE INDEX IF NOT EXISTS idx_user_badge_user  ON user_badge(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badge_badge ON user_badge(badge_id);

-- === Core seeds (modules, groups, global badges) ===
BEGIN;

INSERT INTO module (key, name, active) VALUES
  ('cyberlabs',  'CyberLabs', TRUE),
  ('crucible',   'The Crucible', TRUE),
  ('forge',      'The Forge', TRUE),
  ('university', 'Saguaros University', TRUE),
  ('library',    'The Library', TRUE),
  ('cyberwiki',  'CyberWiki', TRUE)
ON CONFLICT (key) DO NOTHING;

INSERT INTO app_group (key, label, created_at) VALUES
  ('cyberlabs',  'CyberLabs', now()),
  ('crucible',   'The Crucible', now()),
  ('forge',      'The Forge', now()),
  ('university', 'Saguaros University', now()),
  ('library',    'The Library', now()),
  ('cyberwiki',  'CyberWiki', now())
ON CONFLICT (key) DO NOTHING;

-- Global badges (module_key = NULL)
INSERT INTO badge (key, name, description, module_key, icon_url, active) VALUES
  ('member', 'Club Member', 'Verified member of Cyber Saguaros / CyberHub', NULL, NULL, TRUE),
  ('onboarding_complete', 'Onboarding Complete', 'Completed initial onboarding checklist', NULL, NULL, TRUE)
ON CONFLICT (key) DO NOTHING;

COMMIT;