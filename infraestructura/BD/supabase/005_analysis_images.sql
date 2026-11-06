-- Aditiva: los análisis históricos siguen siendo legibles sin imagen.
BEGIN;
ALTER TABLE analyses ADD COLUMN IF NOT EXISTS image_path TEXT;
ALTER TABLE analyses ADD COLUMN IF NOT EXISTS image_sha256 TEXT;
ALTER TABLE analyses ADD COLUMN IF NOT EXISTS image_mime_type TEXT;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = 'analyses'::regclass AND conname = 'analyses_image_fields') THEN
    ALTER TABLE analyses ADD CONSTRAINT analyses_image_fields CHECK (
      (image_path IS NULL AND image_sha256 IS NULL AND image_mime_type IS NULL) OR
      (image_path IS NOT NULL AND image_sha256 IS NOT NULL AND
       image_sha256 ~ '^[0-9a-f]{64}$' AND image_mime_type IS NOT NULL AND
       image_mime_type IN ('image/jpeg', 'image/png'))
    );
  END IF;
END;
$$;
COMMIT;
