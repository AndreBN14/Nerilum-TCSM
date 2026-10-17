"""Integración PostgreSQL: solo DATABASE_URL_TEST y un esquema aleatorio por prueba.

No se lee DATABASE_URL ni se borra contenido de esquemas existentes.
"""
from __future__ import annotations

import os
import json
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
import pytest

from app.core.categories import Category
from app.core.errors import ApiException
from app.core.history_sort import HistorySort
from app.core.model_info import ModelInfo
from app.services import analyses_pg
from app.routes.analyses import _to_out, _summary_from_record

ALICE = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
BOB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"


@pytest.fixture
def repo():
    # Lectura en la fixture: nunca hay fallback a la base de la aplicación.
    dsn = os.environ.get("DATABASE_URL_TEST")
    if not dsn:
        pytest.skip("Requiere DATABASE_URL_TEST dedicada; DATABASE_URL no se usa.")
    schema = f"nerilum_test_{uuid4().hex}"
    with psycopg.connect(dsn, autocommit=True) as admin:
        admin.execute(sql.SQL("CREATE SCHEMA {}").format(sql.Identifier(schema)))
        try:
            isolated_dsn = make_conninfo(dsn, options=f"-csearch_path={schema}")
            repository = analyses_pg.PostgresAnalysisRepository(isolated_dsn)
            try:
                yield repository
            finally:
                repository.close()
        finally:
            admin.execute(sql.SQL("DROP SCHEMA {} CASCADE").format(sql.Identifier(schema)))


def _record(record_id="an_fijo", account=ALICE, created_at="2026-10-12T10:00:00Z",
            name=None, probability=0.25):
    return analyses_pg.AnalysisRecord(
        id=record_id, account_id=account, category="NonDemented",
        probability=probability, scores={c.value: 0.25 for c in Category},
        display_name=name, model_name="yolov8n-cls", model_version="v0.1",
        model_dataset="Alzheimer MRI Dataset (Kaggle)", created_at=created_at,
    )


def test_pg_create_get_list_basic(repo):
    stored = repo.create(_record())
    got = repo.get_by_account(stored.id, ALICE)
    assert got is not None
    assert got.account_id == ALICE
    assert got.created_at == "2026-10-12T10:00:00Z"


def test_pg_pagination_and_order_desc(repo):
    repo.create(_record("an_a"))
    repo.create(_record("an_b"))
    repo.create(_record("an_c", created_at="2026-10-12T11:00:00Z"))
    items, total = repo.list_by_account(ALICE, limit=2, offset=1)
    assert total == 3
    assert [item.id for item in items] == ["an_b", "an_a"]


def test_pg_isolation_per_account(repo):
    repo.create(_record("an_a", ALICE))
    repo.create(_record("an_b", BOB))
    assert repo.get_by_account("an_b", ALICE) is None
    items, total = repo.list_by_account(ALICE, limit=50, offset=0)
    assert total == 1
    assert [item.id for item in items] == ["an_a"]


def test_pg_uuid_owner_and_rls_block_direct_client_roles(repo):
    with repo._connect() as conn:
        table = conn.execute(
            "SELECT relrowsecurity FROM pg_class WHERE oid = 'analyses'::regclass"
        ).fetchone()
        assert table["relrowsecurity"] is True
        owner = conn.execute(
            "SELECT atttypid::regtype::text AS type FROM pg_attribute "
            "WHERE attrelid = 'analyses'::regclass AND attname = 'account_id'"
        ).fetchone()
        assert owner["type"] == "uuid"
        probability_type = conn.execute(
            "SELECT atttypid::regtype::text AS type FROM pg_attribute "
            "WHERE attrelid = 'analyses'::regclass AND attname = 'probability'"
        ).fetchone()
        assert probability_type["type"] == "double precision"
        for role in ("anon", "authenticated"):
            exists = conn.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role,)).fetchone()
            if exists:
                privileges = conn.execute(
                    "SELECT has_table_privilege(%s, 'analyses', 'SELECT') AS can_select, "
                    "has_table_privilege(%s, 'analyses', 'INSERT') AS can_insert",
                    (role, role),
                ).fetchone()
                assert privileges == {"can_select": False, "can_insert": False}


def test_pg_seed_demo_idempotent(repo):
    model = ModelInfo(name="yolov8n-cls", version="v0.1", dataset="Kaggle",
                      classes=[c.value for c in Category])
    assert repo.seed_demo(ALICE, model) == 4
    assert repo.seed_demo(ALICE, model) == 0
    items, total = repo.list_by_account(ALICE, limit=100, offset=0)
    assert total == 4
    assert all(item.is_demo for item in items)


def test_pg_create_raises_internal_error_on_id_collision(repo, monkeypatch):
    monkeypatch.setattr(analyses_pg, "_new_id", lambda: "an_fijo")
    repo.create(_record())
    with pytest.raises(ApiException) as exc:
        repo.create(_record())
    assert exc.value.code == "internal_error"


@pytest.mark.parametrize("sort,expected", [
    (HistorySort.newest, ["an_d", "an_b", "an_a", "an_c"]),
    (HistorySort.oldest, ["an_c", "an_a", "an_b", "an_d"]),
    (HistorySort.name_az, ["an_b", "an_c", "an_a", "an_d"]),
    (HistorySort.probability, ["an_b", "an_c", "an_a", "an_d"]),
])
def test_pg_orders_before_pagination(repo, sort, expected):
    repo.create(_record("an_a", name="Zeta", probability=0.5))
    repo.create(_record("an_b", name="alfa", probability=0.9,
                        created_at="2026-10-12T11:00:00Z"))
    repo.create(_record("an_c", name="Alfa", probability=0.9,
                        created_at="2026-10-12T09:00:00Z"))
    repo.create(_record("an_d", name=None, probability=0.1,
                        created_at="2026-10-12T12:00:00Z"))
    items, total = repo.list_by_account(ALICE, limit=2, offset=1, sort=sort)
    assert total == 4
    assert [item.id for item in items] == expected[1:3]


@pytest.mark.parametrize("probability", [0.9274, 0.84, 0.9, 0.333333, 0.999999])
def test_pg_probability_matches_json_after_reading(repo, probability):
    record = _record(probability=probability)
    record.scores = {
        category.value: probability if category.value == record.category
        else (1 - probability) / 3
        for category in Category
    }
    original = _to_out(record).model_dump(mode="json")
    repo.create(record)
    detail = repo.get_by_account(record.id, ALICE)
    items, total = repo.list_by_account(ALICE, limit=10, offset=0)

    assert detail is not None
    assert total == 1
    for loaded in (detail, items[0]):
        assert loaded.probability == probability
        assert loaded.probability == loaded.scores[loaded.category]
    assert _to_out(detail).model_dump(mode="json") == original
    summary = _summary_from_record(items[0]).model_dump(mode="json")
    assert summary["probability"] == summary["scores"][summary["category"]]


def _precision_migration():
    path = Path(__file__).resolve().parents[1] / "migrations" / "003_align_probability_precision.sql"
    return path.read_text(encoding="utf-8")


def test_pg_migration_recovers_legacy_precision_from_scores(repo):
    record = _record(probability=0.9274)
    record.scores = {
        c.value: record.probability if c.value == record.category
        else (1 - record.probability) / 3 for c in Category
    }
    repo.create(record)
    with repo._connect() as conn:
        conn.execute("ALTER TABLE analyses ALTER COLUMN probability TYPE REAL")
    legacy = repo.get_by_account(record.id, ALICE)
    assert legacy.probability != legacy.scores[legacy.category]

    with repo._connect() as conn:
        conn.autocommit = True
        conn.execute(_precision_migration())
    restored = repo.get_by_account(record.id, ALICE)
    assert restored.probability == restored.scores[restored.category] == 0.9274
    # La migración es repetible sin alterar nombres, fechas ni scores.
    with repo._connect() as conn:
        conn.autocommit = True
        conn.execute(_precision_migration())
    assert repo.get_by_account(record.id, ALICE) == restored


def test_pg_migration_aborts_without_changing_invalid_legacy_rows(repo):
    repo.create(_record(probability=0.9274))
    with repo._connect() as conn:
        conn.execute("ALTER TABLE analyses ALTER COLUMN probability TYPE REAL")
        conn.execute("UPDATE analyses SET scores_json = %s", (json.dumps({}),))
    before = repo.get_by_account("an_fijo", ALICE)

    with pytest.raises(psycopg.Error):
        with repo._connect() as conn:
            conn.autocommit = True
            conn.execute(_precision_migration())

    assert repo.get_by_account("an_fijo", ALICE) == before
    with repo._connect() as conn:
        column = conn.execute(
            "SELECT atttypid::regtype::text AS type FROM pg_attribute "
            "WHERE attrelid = 'analyses'::regclass AND attname = 'probability'"
        ).fetchone()
        assert column["type"] == "real"


def _keyed_record(record_id, account=ALICE, request_hash="a" * 64):
    record = _record(record_id, account)
    record.idempotency_key = "operation-1"
    record.request_hash = request_hash
    return record


def test_pg_idempotent_create_replay_and_conflict(repo):
    first = repo.create(_keyed_record("an_first"))
    repeated = repo.create(_keyed_record("an_second"))
    assert repeated == first
    assert repo.get_by_idempotency_key(ALICE, "operation-1", "a" * 64) == first
    with pytest.raises(ApiException) as exc:
        repo.create(_keyed_record("an_third", request_hash="b" * 64))
    assert exc.value.code == "idempotency_conflict"
    assert repo.list_by_account(ALICE, limit=10, offset=0)[1] == 1
    assert repo.create(_keyed_record("an_bob", account=BOB)).id == "an_bob"


def test_pg_concurrent_key_is_unique(repo):
    with ThreadPoolExecutor(max_workers=4) as executor:
        records = list(executor.map(
            lambda n: repo.create(_keyed_record(f"an_{n}")), range(4)))
    assert len({record.id for record in records}) == 1
    assert repo.list_by_account(ALICE, limit=10, offset=0)[1] == 1


def test_pg_idempotency_migration_preserves_existing_history(repo):
    record = repo.create(_record())
    with repo._connect() as conn:
        conn.execute("ALTER TABLE analyses DROP COLUMN idempotency_key")
        conn.execute("ALTER TABLE analyses DROP COLUMN request_hash")
    migration = Path(__file__).resolve().parents[1] / "migrations" / "004_analysis_idempotency.sql"
    with repo._connect() as conn:
        conn.autocommit = True
        conn.execute(migration.read_text(encoding="utf-8"))
    assert repo.get_by_account(record.id, ALICE) == record
    # Una segunda aplicación no elimina datos ni crea restricciones duplicadas.
    with repo._connect() as conn:
        conn.autocommit = True
        conn.execute(migration.read_text(encoding="utf-8"))
    assert repo.get_by_account(record.id, ALICE) == record
