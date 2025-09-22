-- CyberLabs module: enabled tables + badges

-- Ensure module exists
INSERT INTO module (key, name, active)
VALUES ('cyberlabs', 'CyberLabs', TRUE)
ON CONFLICT (key) DO NOTHING;

-- Module tables (enabled)
CREATE TABLE IF NOT EXISTS cyberlabs_lab (
  lab_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title      TEXT NOT NULL,
  spec       JSONB NOT NULL DEFAULT '{}'::jsonb,   -- store lab params, VM templates, etc.
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- (Optional) VM request table if you want to track asks separately from built resources
CREATE TABLE IF NOT EXISTS cyberlabs_vm_request (
  request_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requested_by UUID NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  purpose      TEXT,
  count        INT NOT NULL DEFAULT 1,
  spec_vcpu    INT,
  spec_ram_mb  INT,
  spec_storage_gb INT,
  spec_gpu_count INT,
  spec_gpu_model TEXT,
  network_profile TEXT,
  requested_duration_hours INT,
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','denied','canceled','fulfilled','expired')),
  approver_user UUID REFERENCES app_user(user_id),
  decided_at   TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Module-scoped badges
INSERT INTO badge (key, name, description, module_key, active) VALUES
  ('cyberlabs_vm_ready', 'VM Ready', 'Requested and launched first lab VM', 'cyberlabs', TRUE),
  ('cyberlabs_vm_poweruser', 'VM Power User', 'Launched 10+ lab VMs', 'cyberlabs', TRUE)
ON CONFLICT (key) DO NOTHING;