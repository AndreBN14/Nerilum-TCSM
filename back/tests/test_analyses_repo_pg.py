"""Pruebas del repositorio Postgres con psycopg v3.

Si no hay DATABASE_URL_TEST configurada, las pruebas se omiten explícitamente.
No se ejecutan pruebas destructivas contra producción.
"""
from __future__ import annotations

import json
import os
import re

import pytest

from app.core.categories import Category
from app.core.errors import ApiException
from app.core.model_info import ModelInfo
from app.services import analyses_pg

CANONICAL_TS = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

DATABASE_URL_TEST = os.environ.get("DATABASE_URL_TEST") or os.environ.get("DATABASE_URL")


def _skip_if_no_pg():
    if not DATABASE_URL_TEST:
        pytest.skip("No hay base de datos Postgres de prueba disponible (falta DATABASE_URL_TEST/DATABASE_URL); saltando pruebas Postgres")


def _make_model_info() -> ModelInfo:
    return ModelInfo(
        name="yolov8n-cls",
        version="v0.1",
        dataset="Alzheimer MRI Dataset (Kaggle)",
        classes=[c.value for c in Category],
    )


def _record_pg(record_id: str = "an_fijo", account: str = "a") -> analyses_pg.AnalysisRecord:
    return analyses_pg.AnalysisRecord(
        id=record_id,
        account_id=account,
        category="NonDemented",
        probability=0.9,
        scores={"NonDemented": 0.9},
        model_name="yolov8n-cls",
        model_version="v0.1",
        model_dataset="Alzheimer MRI Dataset (Kaggle)",
    )


def _full_record_pg(record_id: str, created_at: str, account: str = "a") -> analyses_pg.AnalysisRecord:
    return analyses_pg.AnalysisRecord(
        id=record_id,
        account_id=account,
        category="NonDemented",
        probability=0.25,
        scores={c.value: 0.25 for c in Category},
        model_name="yolov8n-cls",
        model_version="v0.1",
        model_dataset="Alzheimer MRI Dataset (Kaggle)",
        created_at=created_at,
    )


@pytest.mark.skipif(not DATABASE_URL_TEST, reason="Requiere DATABASE_URL_TEST/DATABASE_URL para Postgres")
def test_pg_create_get_list_basic():
    _skip_if_no_pg()
    repo = analyses_pg.PostgresAnalysisRepository(DATABASE_URL_TEST)
    try:
        # limpiar registros de prueba si existen
        with repo._connect() as conn:
            conn.execute("DELETE FROM analyses WHERE account_id IN ('a','b','pgtest')")
            conn.commit()
        stored = repo.create(_record_pg(account="a"))
        assert CANONICAL_TS.match(stored.created_at)
        got = repo.get_by_account("an_fijo", "a")
        assert got is not None
        assert got.id == "an_fijo"
        assert got.account_id == "a"
    finally:
        try:
            with repo._connect() as conn:
                conn.execute("DELETE FROM analyses WHERE account_id IN ('a','b','pgtest')")
                conn.commit()
        except Exception:
            pass
        repo.close()


@pytest.mark.skipif(not DATABASE_URL_TEST, reason="Requiere DATABASE_URL_TEST/DATABASE_URL para Postgres")
def test_pg_pagination_and_order_desc():
    _skip_if_no_pg()
    repo = analyses_pg.PostgresAnalysisRepository(DATABASE_URL_TEST)
    try:
        with repo._connect() as conn:
            conn.execute("DELETE FROM analyses WHERE account_id='a'")
            conn.commit()
        repo.create(_full_record_pg("an_a", "2026-10-12T10:00:00Z", "a"))
        repo.create(_full_record_pg("an_b", "2026-10-12T10:00:00Z", "a"))
        repo.create(_full_record_pg("an_c", "2026-10-12T11:00:00Z", "a"))
        items, total = repo.list_by_account("a", limit=10, offset=0)
        assert total == 3
        assert [i.id for i in items] == ["an_c", "an_b", "an_a"]
    finally:
        try:
            with repo._connect() as conn:
                conn.execute("DELETE FROM analyses WHERE account_id='a'")
                conn.commit()
        except Exception:
            pass
        repo.close()


@pytest.mark.skipif(not DATABASE_URL_TEST, reason="Requiere DATABASE_URL_TEST/DATABASE_URL para Postgres")
def test_pg_isolation_per_account():
    _skip_if_no_pg()
    repo = analyses_pg.PostgresAnalysisRepository(DATABASE_URL_TEST)
    try:
        with repo._connect() as conn:
            conn.execute("DELETE FROM analyses WHERE account_id IN ('a','b')")
            conn.commit()
        repo.create(_record_pg("an_a1", "a"))
        repo.create(_record_pg("an_b1", "b"))
        got_a = repo.get_by_account("an_b1", "a")
        assert got_a is None
        got_b = repo.get_by_account("an_b1", "b")
        assert got_b is not None
        items_b, total_b = repo.list_by_account("b", limit=50, offset=0)
        assert total_b == 1
        items_a, total_a = repo.list_by_account("a", limit=50, offset=0)
        assert total_a == 1
    finally:
        try:
            with repo._connect() as conn:
                conn.execute("DELETE FROM analyses WHERE account_id IN ('a','b')")
                conn.commit()
        except Exception:
            pass
        repo.close()


@pytest.mark.skipif(not DATABASE_URL_TEST, reason="Requiere DATABASE_URL_TEST/DATABASE_URL para Postgres")
def test_pg_scores_and_created_at_canonical():
    _skip_if_no_pg()
    repo = analyses_pg.PostgresAnalysisRepository(DATABASE_URL_TEST)
    try:
        with repo._connect() as conn:
            conn.execute("DELETE FROM analyses WHERE account_id='a'")
            conn.commit()
        repo.create(_record_pg("an_s", "a"))
        got = repo.get_by_account("an_s", "a")
        assert got is not None
        assert CANONICAL_TS.match(got.created_at)
        assert "NonDemented" in got.scores
    finally:
        try:
            with repo._connect() as conn:
                conn.execute("DELETE FROM analyses WHERE account_id='a'")
                conn.commit()
        except Exception:
            pass
        repo.close()


@pytest.mark.skipif(not DATABASE_URL_TEST, reason="Requiere DATABASE_URL_TEST/DATABASE_URL para Postgres")
def test_pg_seed_demo_idempotent_and_fields():
    _skip_if_no_pg()
    repo = analyses_pg.PostgresAnalysisRepository(DATABASE_URL_TEST)
    try:
        acc = "pgtest"
        with repo._connect() as conn:
            conn.execute("DELETE FROM analyses WHERE account_id=%s", (acc,))
            conn.commit()
        mi = _make_model_info()
        n1 = repo.seed_demo(acc, mi)
        n2 = repo.seed_demo(acc, mi)
        assert n1 == 4
        assert n2 == 0
        items, total = repo.list_by_account(acc, limit=100, offset=0)
        assert total == 4
        assert all(i.is_demo for i in items)
        assert all(i.model_dataset == mi.dataset for i in items)
    finally:
        try:
            with repo._connect() as conn:
                conn.execute("DELETE FROM analyses WHERE account_id='pgtest'")
                conn.commit()
        except Exception:
            pass
        repo.close()


@pytest.mark.skipif(not DATABASE_URL_TEST, reason="Requiere DATABASE_URL_TEST/DATABASE_URL para Postgres")
def test_pg_create_raises_internal_error_on_id_collision(monkeypatch):
    _skip_if_no_pg()
    repo = analyses_pg.PostgresAnalysisRepository(DATABASE_URL_TEST)
    try:
        with repo._connect() as conn:
            conn.execute("DELETE FROM analyses WHERE account_id='a'")
            conn.commit()
        monkeypatch.setattr(analyses_pg, "_new_id", lambda: "an_fijo")
        repo.create(_record_pg("an_fijo", "a"))
        with pytest.raises(ApiException) as exc:
            repo.create(_record_pg("an_fijo", "a"))
        assert exc.value.status_code == 500
        assert exc.value.code == "internal_error"
    finally:
        try:
            with repo._connect() as conn:
                conn.execute("DELETE FROM analyses WHERE account_id='a'")
                conn.commit()
        except Exception:
            pass
        repo.close()
