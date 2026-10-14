-- Creación de tabla analyses para persistencia Postgres
-- Sin DDL destructivo: CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS
CREATE TABLE IF NOT EXISTS analyses (
  id            TEXT PRIMARY KEY,
  account_id    TEXT NOT NULL,
  category      TEXT NOT NULL,
  probability   REAL NOT NULL,
  scores_json   TEXT NOT NULL,
  display_name  TEXT,
  is_demo       BOOLEAN NOT NULL DEFAULT FALSE,
  model_name    TEXT NOT NULL,
  model_version TEXT NOT NULL,
  model_dataset TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_analyses_account_created
  ON analyses (account_id, created_at DESC);
