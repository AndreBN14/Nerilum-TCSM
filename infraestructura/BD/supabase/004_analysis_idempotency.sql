-- Actualización aditiva: sin borrar ni modificar resultados anteriores.
BEGIN;
ALTER TABLE analyses ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE analyses ADD COLUMN IF NOT EXISTS request_hash TEXT;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = 'analyses'::regclass AND conname = 'analyses_account_idempotency_key') THEN
    ALTER TABLE analyses ADD CONSTRAINT analyses_account_idempotency_key
      UNIQUE (account_id, idempotency_key);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = 'analyses'::regclass AND conname = 'analyses_idempotency_pair') THEN
    ALTER TABLE analyses ADD CONSTRAINT analyses_idempotency_pair CHECK (
      (idempotency_key IS NULL AND request_hash IS NULL) OR
      (idempotency_key IS NOT NULL AND request_hash IS NOT NULL
        AND idempotency_key ~ '^[A-Za-z0-9._:-]{1,128}$'
        AND request_hash ~ '^[0-9a-f]{64}$')
    );
  END IF;
END;
$$;
COMMIT;
