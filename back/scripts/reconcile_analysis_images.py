"""Limpia originales huérfanos con más de un día; solo borra con --apply.

Ejecutar tras migrar la base y configurar SUPABASE_SERVICE_ROLE_KEY:
    python -m scripts.reconcile_analysis_images
    python -m scripts.reconcile_analysis_images --apply
"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone

from app.core.config import get_settings
from app.services.analyses import SqliteAnalysisRepository
from app.services.analyses_pg import PostgresAnalysisRepository
from app.services.image_storage import SupabaseImageStorage


def reconcile(*, apply: bool = False) -> tuple[int, int]:
    settings = get_settings()
    if not settings.supabase_service_role_key:
        raise RuntimeError("Falta SUPABASE_SERVICE_ROLE_KEY")
    repository = (PostgresAnalysisRepository(settings.database_url)
                  if settings.database_url else SqliteAnalysisRepository(settings.database_path))
    storage = SupabaseImageStorage(settings.supabase_url, settings.supabase_service_role_key,
                                   settings.analysis_images_bucket)
    cutoff = datetime.now(timezone.utc) - timedelta(days=1)
    inspected = removed = 0
    try:
        referenced = repository.list_image_paths()

        def walk(prefix: str = ""):
            offset = 0
            while True:
                rows = storage.list(prefix, offset=offset)
                for item in rows:
                    name = item["name"]
                    path = f"{prefix}/{name}" if prefix else name
                    if item.get("id") is None:
                        yield from walk(path)
                    else:
                        yield path, item
                if len(rows) < 100:
                    break
                offset += len(rows)

        for path, item in walk():
            inspected += 1
            created = item.get("created_at")
            if not created or path in referenced:
                continue
            date = datetime.fromisoformat(created.replace("Z", "+00:00"))
            if date >= cutoff:
                continue
            if apply:
                # Volver a consultar antes de borrar en caso de un guardado
                # concurrente entre la lectura inicial y la limpieza.
                if path in repository.list_image_paths():
                    continue
                storage.remove(path)
            removed += 1
        return inspected, removed
    finally:
        storage.close()
        repository.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Reconciliar imágenes sin análisis")
    parser.add_argument("--apply", action="store_true", help="Borrar huérfanos antiguos")
    args = parser.parse_args()
    total, orphans = reconcile(apply=args.apply)
    print(f"Objetos revisados: {total}; huérfanos {'borrados' if args.apply else 'detectados'}: {orphans}")
