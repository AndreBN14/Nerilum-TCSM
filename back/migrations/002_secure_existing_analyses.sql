-- Ejecutar explícitamente para una instalación que ya tenga account_id TEXT.
-- Si hay propietarios que no sean UUID, aborta sin borrar registros.
BEGIN;
ALTER TABLE analyses ALTER COLUMN account_id TYPE UUID USING account_id::uuid;
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
COMMIT;
