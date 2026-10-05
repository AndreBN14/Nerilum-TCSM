# PostgreSQL en Supabase

Este SQL es una copia idéntica de `supabase/migrations/202610040001_create_profiles.sql`.
Ejecutar **una sola copia una sola vez**, en SQL Editor del proyecto Supabase, o aplicar
la migración con Supabase CLI. Requiere `auth.users`, los roles de Supabase y `auth.uid()`;
no es un esquema para PostgreSQL independiente sin Supabase Auth.

Solo crea `profiles` con triggers y RLS. Supabase administra `auth.users` y las contraseñas.
No se crean tablas de diagnósticos, imágenes ni resultados.
