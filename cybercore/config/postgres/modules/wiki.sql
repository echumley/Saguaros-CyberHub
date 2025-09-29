INSERT INTO module (key, name, active)
VALUES ('wiki', 'The Wiki', TRUE)
ON CONFLICT (key) DO NOTHING;
