-- kind: expand
-- Rehearsal of a migration that passes on a fresh database and fails on real data (docs/ec2-to-ecs.md,
-- step 6). It validates every existing row, so one note over 200 characters stops it. Removed after.
ALTER TABLE notes ADD CONSTRAINT notes_body_at_most_200 CHECK (char_length(body) <= 200);
