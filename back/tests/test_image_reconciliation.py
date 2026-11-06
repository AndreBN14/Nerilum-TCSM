"""La limpieza espera la ventana de reintentos y nunca toca filas asociadas."""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from scripts import reconcile_analysis_images as job


def test_reconcile_only_removes_old_unreferenced_objects(monkeypatch):
    old = (datetime.now(timezone.utc) - timedelta(days=2)).isoformat()
    recent = datetime.now(timezone.utc).isoformat()

    class Repository:
        def __init__(self, _):
            pass

        def list_image_paths(self):
            return {"owner/an_saved.png"}

        def close(self):
            pass

    class Storage:
        removed = []

        def __init__(self, *_):
            pass

        def list(self, prefix="", **_):
            if prefix == "":
                return [{"id": None, "name": "owner"}]
            return [
                {"id": "a", "name": "an_saved.png", "created_at": old},
                {"id": "b", "name": "an_orphan.png", "created_at": old},
                {"id": "c", "name": "an_recent.png", "created_at": recent},
            ]

        def remove(self, path):
            self.removed.append(path)

        def close(self):
            pass

    monkeypatch.setattr(job, "get_settings", lambda: SimpleNamespace(
        database_url=None, database_path=":memory:",
        supabase_url="https://test.supabase.co", supabase_service_role_key="test-key",
        analysis_images_bucket="analysis-images"))
    monkeypatch.setattr(job, "SqliteAnalysisRepository", Repository)
    monkeypatch.setattr(job, "SupabaseImageStorage", Storage)
    assert job.reconcile() == (3, 1)
    assert Storage.removed == []
    assert job.reconcile(apply=True) == (3, 1)
    assert Storage.removed == ["owner/an_orphan.png"]
