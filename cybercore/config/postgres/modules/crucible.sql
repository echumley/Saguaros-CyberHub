-- Crucible (CTF range) module: enabled tables + badges

INSERT INTO module (key, name, active)
VALUES ('crucible', 'The Crucible', TRUE)
ON CONFLICT (key) DO NOTHING;

-- Module tables (enabled)
CREATE TABLE IF NOT EXISTS crucible_event (
  event_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  starts_at  TIMESTAMPTZ,
  ends_at    TIMESTAMPTZ,
  metadata   JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS crucible_score (
  score_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id   UUID NOT NULL REFERENCES crucible_event(event_id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  points     INT NOT NULL DEFAULT 0,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, user_id)
);

-- Module-scoped badges
INSERT INTO badge (key, name, description, module_key, active) VALUES
  ('crucible_ctf_scorer', 'CTF Scorer', 'Scored in a Crucible CTF event', 'crucible', TRUE),
  ('crucible_ctf_winner', 'CTF Winner', 'Won a Crucible CTF event', 'crucible', TRUE)
ON CONFLICT (key) DO NOTHING;