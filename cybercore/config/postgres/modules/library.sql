INSERT INTO module (key, name, active)
VALUES ('library', 'The Library', TRUE)
ON CONFLICT (key) DO NOTHING;
