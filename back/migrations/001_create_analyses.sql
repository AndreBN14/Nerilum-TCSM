-- Resultados accesibles exclusivamente desde el backend, no desde PostgREST.
CREATE TABLE IF NOT EXISTS analyses (
  id            TEXT PRIMARY KEY,
  account_id    UUID NOT NULL,
  category      TEXT NOT NULL,
  probability   DOUBLE PRECISION NOT NULL,
  scores_json   TEXT NOT NULL,
  display_name  TEXT,
  is_demo       BOOLEAN NOT NULL DEFAULT FALSE,
  model_name    TEXT NOT NULL,
  model_version TEXT NOT NULL,
  model_dataset TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL,
  idempotency_key TEXT,
  request_hash TEXT,
  CONSTRAINT analyses_account_idempotency_key UNIQUE (account_id, idempotency_key),
  CONSTRAINT analyses_idempotency_pair CHECK (
    (idempotency_key IS NULL AND request_hash IS NULL) OR
    (idempotency_key IS NOT NULL AND request_hash IS NOT NULL
      AND idempotency_key ~ '^[A-Za-z0-9._:-]{1,128}$'
      AND request_hash ~ '^[0-9a-f]{64}$')
  )
);

CREATE INDEX IF NOT EXISTS idx_analyses_account_created
  ON analyses (account_id, created_at DESC);

ALTER TABLE analyses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE analyses FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE analyses FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE analyses FROM authenticated;
  END IF;
END;
$$;
