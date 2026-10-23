-- kind: expand
-- Nullable, so code that does not know the column yet keeps inserting.
ALTER TABLE notes ADD COLUMN IF NOT EXISTS author TEXT;
