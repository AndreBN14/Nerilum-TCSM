-- REAL (float32) puede alterar una puntuación conservada en scores_json.
-- Cambiar el tipo no recupera los bits perdidos: restaurar desde el JSON.
-- Si una fila no permite esa recuperación, abortar toda la migración.
BEGIN;
LOCK TABLE analyses IN ACCESS EXCLUSIVE MODE;

DO $$
DECLARE
  record_data record;
  payload json;
  score double precision;
BEGIN
  FOR record_data IN SELECT id, category, scores_json FROM analyses LOOP
    payload := record_data.scores_json::json;
    IF json_typeof(payload) IS DISTINCT FROM 'object'
       OR json_typeof(payload -> record_data.category) IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'No se puede recuperar la probabilidad de un registro. Revisar scores_json y category.';
    END IF;
    score := (payload ->> record_data.category)::double precision;
    IF score IS NULL OR NOT (score >= 0 AND score <= 1) THEN
      RAISE EXCEPTION 'Hay puntuaciones fuera del rango permitido. No se ha aplicado la migración.';
    END IF;
  END LOOP;
END;
$$;

ALTER TABLE analyses ALTER COLUMN probability TYPE DOUBLE PRECISION
  USING probability::double precision;

UPDATE analyses
SET probability = (scores_json::json ->> category)::double precision
WHERE probability IS DISTINCT FROM (scores_json::json ->> category)::double precision;

COMMIT;
