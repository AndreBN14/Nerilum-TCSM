from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from typing import Protocol

import psycopg
from psycopg import errors as pg_errors

from app.core.errors import ApiException
from app.core.model_info import ModelInfo
from app.services.analyses import (
    AnalysisRecord,
    AnalysisRepository,
    DemoRecord,
    ModelInfo,
    _demo_scores,
    _format_utc,
    _new_id,
    _normalize_created_at,
    _now_iso,
)


def _pg_normalize_created_at(value) -> str:
    """Convierte valor TIMESTAMPTZ/datetime/str a formato UTC con Z."""
    if value is None:
        return _now_iso()
    if isinstance(value, datetime):
        dt = value
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    if isinstance(value, str):
        return _normalize_created_at(value)
    return str(value)


class PostgresAnalysisRepository(AnalysisRepository, Protocol):
    """Repositorio Postgres con psycopg v3 sincrónico."""

    def __init__(self, database_url: str) -> None:
        if not database_url or not str(database_url).strip():
            raise ValueError("DATABASE_URL vacío; no se puede inicializar PostgresAnalysisRepository")
        self._dsn = str(database_url).strip()
        self.ensure_schema()

    def _connect(self):
        conn = psycopg.Connection.connect(self._dsn, row_factory=psycopg.rows.dict_row, autocommit=False)
        return conn

    def ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS analyses (
                    id            TEXT PRIMARY KEY,
                    account_id    TEXT NOT NULL,
                    category      TEXT NOT NULL,
                    probability   REAL NOT NULL,
                    scores_json   TEXT NOT NULL,
                    display_name  TEXT,
                    is_demo       BOOLEAN NOT NULL DEFAULT FALSE,
                    model_name    TEXT NOT NULL,
                    model_version TEXT NOT NULL,
                    model_dataset TEXT NOT NULL,
                    created_at    TIMESTAMPTZ NOT NULL
                )
                """
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_analyses_account_created ON analyses (account_id, created_at DESC)"
            )
            conn.commit()

    def create(self, record: AnalysisRecord) -> AnalysisRecord:
        with self._connect() as conn:
            for _ in range(3):
                try:
                    conn.execute(
                        """
                        INSERT INTO analyses (
                            id, account_id, category, probability, scores_json,
                            display_name, is_demo, model_name, model_version,
                            model_dataset, created_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        """,
                        (
                            record.id,
                            record.account_id,
                            record.category,
                            record.probability,
                            json.dumps(record.scores),
                            record.display_name,
                            bool(record.is_demo),
                            record.model_name,
                            record.model_version,
                            record.model_dataset,
                            record.created_at,
                        ),
                    )
                    conn.commit()
                    break
                except (pg_errors.UniqueViolation, sqlite3.IntegrityError, pg_errors.IntegrityError):
                    record.id = _new_id()
                    conn.rollback()
            else:
                raise ApiException(500, "internal_error", "No se pudo guardar el análisis.")
            return record

    def list_by_account(
        self, account_id: str, *, limit: int, offset: int
    ) -> tuple[list[AnalysisRecord], int]:
        with self._connect() as conn:
            total_row = conn.execute(
                "SELECT COUNT(*) AS cnt FROM analyses WHERE account_id = %s",
                (account_id,),
            ).fetchone()
            total = int(total_row["cnt"]) if total_row else 0
            rows = conn.execute(
                """
                SELECT * FROM analyses
                WHERE account_id = %s
                ORDER BY created_at DESC, id DESC
                LIMIT %s OFFSET %s
                """,
                (account_id, limit, offset),
            ).fetchall()
            items = []
            for r in rows:
                item = AnalysisRecord(
                    id=r["id"],
                    account_id=r["account_id"],
                    category=r["category"],
                    probability=float(r["probability"]),
                    scores=json.loads(r["scores_json"]) if isinstance(r["scores_json"], str) else r["scores_json"],
                    display_name=r["display_name"],
                    is_demo=bool(r["is_demo"]),
                    model_name=r["model_name"],
                    model_version=r["model_version"],
                    model_dataset=r["model_dataset"],
                    created_at=_pg_normalize_created_at(r["created_at"]),
                )
                items.append(item)
            return items, int(total)

    def get_by_account(self, analysis_id: str, account_id: str) -> AnalysisRecord | None:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT * FROM analyses
                WHERE id = %s AND account_id = %s
                """,
                (analysis_id, account_id),
            ).fetchone()
        if row is None:
            return None
        return AnalysisRecord(
            id=row["id"],
            account_id=row["account_id"],
            category=row["category"],
            probability=float(row["probability"]),
            scores=json.loads(row["scores_json"]) if isinstance(row["scores_json"], str) else row["scores_json"],
            display_name=row["display_name"],
            is_demo=bool(row["is_demo"]),
            model_name=row["model_name"],
            model_version=row["model_version"],
            model_dataset=row["model_dataset"],
            created_at=_pg_normalize_created_at(row["created_at"]),
        )

    def seed_demo(self, account_id: str, model_info: ModelInfo) -> int:
        demo: list[DemoRecord] = [
            ("Exploración inicial", "MildDemented", 0.84),
            ("Control de seguimiento", "NonDemented", 0.72),
            ("Revisión de imagen", "VeryMildDemented", 0.91),
            ("Estudio de referencia", "ModerateDemented", 0.63),
        ]
        with self._connect() as conn:
            existing_row = conn.execute(
                "SELECT COUNT(*) AS cnt FROM analyses WHERE account_id = %s AND is_demo = TRUE",
                (account_id,),
            ).fetchone()
            existing = int(existing_row["cnt"]) if existing_row else 0
            if existing:
                conn.commit()
                return 0
            for display_name, category, probability in demo:
                scores = _demo_scores(category, probability)
                conn.execute(
                    """
                    INSERT INTO analyses (
                        id, account_id, category, probability, scores_json,
                        display_name, is_demo, model_name, model_version,
                        model_dataset, created_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, TRUE, %s, %s, %s, %s)
                    """,
                    (
                        _new_id(),
                        account_id,
                        category,
                        probability,
                        json.dumps(scores),
                        display_name,
                        model_info.name,
                        model_info.version,
                        model_info.dataset,
                        _now_iso(),
                    ),
                )
            conn.commit()
            return len(demo)

    def close(self) -> None:
        pass
