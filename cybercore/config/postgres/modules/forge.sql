-- The Forge (malware/dev lab) module: enabled tables + badges

INSERT INTO module (key, name, active)
VALUES ('forge', 'The Forge', TRUE)
ON CONFLICT (key) DO NOTHING;

-- Module tables (enabled)
CREATE TABLE IF NOT EXISTS forge_project (
  project_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  repo_url    TEXT,
  meta        JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS forge_artifact (
  artifact_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id  UUID NOT NULL REFERENCES forge_project(project_id) ON DELETE CASCADE,
  kind        TEXT NOT NULL,          -- e.g., 'binary','script','pcap'
  storage_ref TEXT,                    -- path/object key
  meta        JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Module-scoped badges
INSERT INTO badge (key, name, description, module_key, active) VALUES
  ('forge_builder', 'Forge Builder', 'Built a tool or sample in The Forge', 'forge', TRUE),
  ('forge_reverser', 'Reverser', 'Completed a reversing exercise', 'forge', TRUE)
ON CONFLICT (key) DO NOTHING;