-- Saguaros University (LMS) module: enabled tables + badges

INSERT INTO module (key, name, active)
VALUES ('university', 'Saguaros University', TRUE)
ON CONFLICT (key) DO NOTHING;

-- Module tables (enabled)
CREATE TABLE IF NOT EXISTS university_course (
  course_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT NOT NULL UNIQUE,
  title       TEXT NOT NULL,
  meta        JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS university_enrollment (
  enrollment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id     UUID NOT NULL REFERENCES university_course(course_id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  enrolled_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','dropped','completed')),
  UNIQUE (course_id, user_id)
);

-- Module-scoped badges
INSERT INTO badge (key, name, description, module_key, active) VALUES
  ('univ_course_complete', 'Course Complete', 'Completed a University course', 'university', TRUE),
  ('univ_honors', 'Honors', 'Completed a course with distinction', 'university', TRUE)
ON CONFLICT (key) DO NOTHING;