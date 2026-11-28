"""Pruebas de DELETE /api/v1/auth/me (eliminación de cuenta)."""

from __future__ import annotations

from pathlib import Path

from conftest import (
    SUBJECT,
    FakeInference,
    build_app,
    build_verifier,
    sign_token,
)
from fastapi.testclient import TestClient

from app.core.errors import ApiException
from app.services.analyses import AnalysisRecord


class FakeAuthAdmin:
    """Sustituto del Admin API: registra los ids eliminados."""

    def __init__(self, *, fail: bool = False) -> None:
        self.deleted: list[str] = []
        self._fail = fail

    def delete_user(self, user_id: str) -> None:
        if self._fail:
            raise ApiException(
                503, "auth_admin_unavailable", "fallo simulado"
            )
        self.deleted.append(user_id)

    def close(self) -> None:
        return None


class FakeStorage:
    """Sustituto de Storage que registra los prefijos borrados."""

    def __init__(self, *, fail: bool = False) -> None:
        self.removed: list[str] = []
        self._fail = fail

    def put(self, path: str, content: bytes, mime_type: str) -> None:
        raise NotImplementedError

    def get(self, path: str) -> bytes:
        raise NotImplementedError

    def remove(self, path_or_prefix: str) -> None:
        if self._fail:
            raise ApiException(
                503, "storage_unavailable", "fallo simulado"
            )
        self.removed.append(path_or_prefix)

    def close(self) -> None:
        return None


def _app(stub, *, auth_admin=None, image_storage=None, db_path: Path | None = None) -> TestClient:
    return TestClient(
        build_app(
            build_verifier(stub),
            inference=FakeInference(),
            db_path=db_path,
            image_storage=image_storage,
            auth_admin=auth_admin,
        )
    )


def _record(account_id: str, analysis_id: str) -> AnalysisRecord:
    return AnalysisRecord(
        account_id=account_id,
        category="NonDemented",
        probability=0.5,
        scores={"NonDemented": 0.5, "VeryMildDemented": 0.2,
               "MildDemented": 0.1, "ModerateDemented": 0.2},
        model_name="fake-cls",
        model_version="test",
        model_dataset="ADNI",
        display_name="prueba",
        id=analysis_id,
    )


def test_delete_requires_auth(stub):
    with _app(stub, auth_admin=FakeAuthAdmin()) as client:
        response = client.delete("/api/v1/auth/me")
    assert response.status_code == 401


def test_delete_without_service_key_returns_503(stub, keypair):
    with _app(stub, auth_admin=None) as client:
        response = client.delete(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer {sign_token(keypair)}"}
        )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "account_deletion_unavailable"


def test_delete_removes_own_data_only(stub, keypair, tmp_path):
    other_account = "22222222-2222-2222-2222-222222222222"
    admin = FakeAuthAdmin()
    storage = FakeStorage()
    with _app(stub, auth_admin=admin, image_storage=storage,
              db_path=tmp_path / "db.sqlite") as client:
        repo = client.app.state.services.analyses
        repo.create(_record(SUBJECT, "an_own_1"))
        repo.create(_record(SUBJECT, "an_own_2"))
        repo.create(_record(other_account, "an_other_1"))

        response = client.delete(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {sign_token(keypair)}"},
        )

    assert response.status_code == 204
    # Solo se borran los datos de la cuenta autenticada.
    _, own_total = repo.list_by_account(SUBJECT, limit=10, offset=0)
    assert own_total == 0
    assert repo.get_by_account("an_other_1", other_account) is not None
    # Storage: carpeta completa del usuario por prefijo.
    assert storage.removed == [f"{SUBJECT}/"]
    # El usuario de Supabase Auth se elimina al final, una sola vez.
    assert admin.deleted == [SUBJECT]


def test_delete_survives_storage_failure(stub, keypair, tmp_path):
    admin = FakeAuthAdmin()
    storage = FakeStorage(fail=True)
    with _app(stub, auth_admin=admin, image_storage=storage,
              db_path=tmp_path / "db.sqlite") as client:
        repo = client.app.state.services.analyses
        repo.create(_record(SUBJECT, "an_own_1"))

        response = client.delete(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {sign_token(keypair)}"},
        )

    # El fallo de Storage (best-effort) no cancela la eliminación.
    assert response.status_code == 204
    _, own_total = repo.list_by_account(SUBJECT, limit=10, offset=0)
    assert own_total == 0
    assert admin.deleted == [SUBJECT]


def test_delete_propagates_admin_failure(stub, keypair, tmp_path):
    admin = FakeAuthAdmin(fail=True)
    with _app(stub, auth_admin=admin, db_path=tmp_path / "db.sqlite") as client:
        response = client.delete(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {sign_token(keypair)}"},
        )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "auth_admin_unavailable"
