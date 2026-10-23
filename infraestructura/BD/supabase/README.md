# PostgreSQL en Supabase

Este SQL es una copia idéntica de `supabase/migrations/202610040001_create_profiles.sql`.
Ejecutar **una sola copia una sola vez**, en SQL Editor del proyecto Supabase, o aplicar
la migración con Supabase CLI. Requiere `auth.users`, los roles de Supabase y `auth.uid()`;
no es un esquema para PostgreSQL independiente sin Supabase Auth.

Solo crea `profiles` con triggers y RLS. Supabase administra `auth.users` y las contraseñas.
La migración de perfiles no crea tablas de diagnósticos, imágenes ni resultados.

## Resultados de análisis

`001_create_analyses.sql`, `002_secure_existing_analyses.sql` y
`003_align_probability_precision.sql` son copias de
`back/migrations/`. La primera crea y protege la tabla; la segunda convierte
`account_id` de TEXT a UUID en instalaciones antiguas y restringe acceso directo.
La tercera cambia `probability` a DOUBLE PRECISION y recupera la puntuación exacta
desde `scores_json[category]`. Aborta en transacción si no puede recuperar algún
valor; no se borran registros. Consultar el README del backend para el orden de
actualización de una instalación existente y el bloqueo temporal de la tabla.
No aplicar dos veces copias de una misma migración. Consultar `back/README.md`
antes de actualizar una base existente. No se ejecutaron contra Supabase desde
el agente: deben aplicarse explícitamente al entorno que corresponda.

`004_analysis_idempotency.sql` también es copia de `back/migrations/`: añade
`idempotency_key`, `request_hash` y la restricción única por propietario para
evitar duplicados en reintentos. Es una actualización aditiva; las filas existentes
mantienen ambos campos a null. En instalaciones nuevas ya se incluyen en `001`.
