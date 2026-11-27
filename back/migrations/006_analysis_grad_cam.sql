-- Aditiva: los análisis históricos siguen siendo legibles sin mapa de atención.
BEGIN;

ALTER TABLE analyses ADD COLUMN IF NOT EXISTS grad_cam_path      TEXT;
ALTER TABLE analyses ADD COLUMN IF NOT EXISTS grad_cam_sha256    TEXT;
ALTER TABLE analyses ADD COLUMN IF NOT EXISTS grad_cam_mime_type TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'analyses'::regclass
      AND conname  = 'analyses_grad_cam_fields'
  ) THEN
    ALTER TABLE analyses ADD CONSTRAINT analyses_grad_cam_fields CHECK (
      (grad_cam_path IS NULL AND grad_cam_sha256 IS NULL AND grad_cam_mime_type IS NULL)
      OR
      (grad_cam_path     IS NOT NULL AND
       grad_cam_sha256   IS NOT NULL AND
       grad_cam_sha256   ~ '^[0-9a-f]{64}$' AND
       grad_cam_mime_type IS NOT NULL AND
       grad_cam_mime_type IN ('image/jpeg', 'image/png'))
    );
  END IF;
END;
$$;

COMMIT;
