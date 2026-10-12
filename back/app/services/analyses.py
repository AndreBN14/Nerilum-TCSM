"""Persistencia del historial de análisis en SQLite.

Solo se guarda el resultado del análisis (sin imágenes). Los registros se
aíslan por ``account_id``, que corresponde al UUID validado del JWT de
Supabase; nunca llega del cuerpo de la petición.
"""

from __future__ import annotations

import json
import secrets
import sqlite3
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Protocol

from app.core.errors import ApiException

DemoRecord = tuple[str, str, float]


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def _new_id() -> str:
    return f"an_{secrets.token_hex(6)}"


@dataclass
class AnalysisRecord:
    account_id: str
    category: str
    probability: float
    scores: dict[str, float]
    display_name: str | None = None
    is_demo: bool = False
    model_name: str = "yolov8n-cls"
    model_version: str = "v0.1"
    id: str = field(default_factory=_new_id)
    created_at: str = field(default_factory=_now_iso)

    @staticmethod
    def from_row(row: sqlite3.Row) -> "AnalysisRecord":
        return AnalysisRecord(
            id=row["id"],
            account_id=row["account_id"],
            category=row["category"],
            probability=row["probability"],
            scores=json.loads(row["scores_json"]),
            display_name=row["display_name"],
            is_demo=bool(row["is_demo"]),
            model_name=row["model_name"],
            model_version=row["model_version"],
            created_at=row["created_at"],
        )


class AnalysisRepository(Protocol):
    def create(self, record: AnalysisRecord) -> AnalysisRecord: ...
    def list_by_account(
        self, account_id: str, *, limit: int, offset: int
    ) -> tuple[list[AnalysisRecord], int]: ...
    def get_by_account(self, analysis_id: str, account_id: str) -> AnalysisRecord | None: ...
    def ensure_schema(self) -> None: ...
    def seed_demo(self, account_id: str) -> int: ...
    def close(self) -> None: ...


class SqliteAnalysisRepository:
    """Repositorio SQLite; una conexión breve por operación."""

    def __init__(self, database_path: str | Path) -> None:
        self._path = Path(database_path)
        if str(self._path) != ":memory:":
            self._path.parent.mkdir(parents=True, exist_ok=True)
        self.ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._path)
        conn.row_factory = sqlite3.Row
        return conn

    def ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS analyses (
                    id            TEXT PRIMARY KEY,
                    account_id    TEXT NOT NULL,
                    category      TEXT NOT NULL,
                    probability   REAL NOT NULL,
                    scores_json   TEXT NOT NULL,
                    display_name  TEXT,
                    is_demo       INTEGER NOT NULL DEFAULT 0,
                    model_name    TEXT NOT NULL,
                    model_version TEXT NOT NULL,
                    created_at    TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_analyses_account_created
                    ON analyses (account_id, created_at DESC);
                """
            )

    def create(self, record: AnalysisRecord) -> AnalysisRecord:
        with self._connect() as conn:
            for _ in range(3):
                try:
                    conn.execute(
                        """
                        INSERT INTO analyses (
                            id, account_id, category, probability, scores_json,
                            display_name, is_demo, model_name, model_version, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            record.id,
                            record.account_id,
                            record.category,
                            record.probability,
                            json.dumps(record.scores),
                            record.display_name,
                            int(record.is_demo),
                            record.model_name,
                            record.model_version,
                            record.created_at,
                        ),
                    )
                    break
                except sqlite3.IntegrityError:
                    record.id = _new_id()
            else:
                raise ApiException(500, "internal_error", "No se pudo guardar el análisis.")
            return record

    def list_by_account(
        self, account_id: str, *, limit: int, offset: int
    ) -> tuple[list[AnalysisRecord], int]:
        with self._connect() as conn:
            total = conn.execute(
                "SELECT COUNT(*) FROM analyses WHERE account_id = ?",
                (account_id,),
            ).fetchone()[0]
            rows = conn.execute(
                """
                SELECT * FROM analyses
                WHERE account_id = ?
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
                """,
                (account_id, limit, offset),
            ).fetchall()
        return [AnalysisRecord.from_row(r) for r in rows], int(total)

    def get_by_account(self, analysis_id: str, account_id: str) -> AnalysisRecord | None:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT * FROM analyses
                WHERE id = ? AND account_id = ?
                """,
                (analysis_id, account_id),
            ).fetchone()
        return AnalysisRecord.from_row(row) if row is not None else None

    def seed_demo(self, account_id: str) -> int:
        """Inserta los 4 registros demo si la cuenta aún no tiene ninguno."""
        demo: list[DemoRecord] = [
            ("Exploración inicial", "MildDemented", 0.84),
            ("Control de seguimiento", "NonDemented", 0.72),
            ("Revisión de imagen", "VeryMildDemented", 0.91),
            ("Estudio de referencia", "ModerateDemented", 0.63),
        ]
        with self._connect() as conn:
            existing = conn.execute(
                "SELECT COUNT(*) FROM analyses WHERE account_id = ? AND is_demo = 1",
                (account_id,),
            ).fetchone()[0]
            if existing:
                return 0
            for display_name, category, probability in demo:
                scores = _demo_scores(category, probability)
                conn.execute(
                    """
                    INSERT INTO analyses (
                        id, account_id, category, probability, scores_json,
                        display_name, is_demo, model_name, model_version, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
                    """,
                    (
                        _new_id(),
                        account_id,
                        category,
                        probability,
                        json.dumps(scores),
                        display_name,
                        "yolov8n-cls",
                        "v0.1",
                        _now_iso(),
                    ),
                )
        return len(demo)

    def close(self) -> None:
        # Conexiones por operación; no hay recurso permanente que liberar.
        pass


def _demo_scores(category: str, probability: float) -> dict[str, float]:
    labels = ["NonDemented", "VeryMildDemented", "MildDemented", "ModerateDemented"]
    scores: dict[str, float] = {}
    resto = (1.0 - probability) / (len(labels) - 1)
    for label in labels:
        scores[label] = round(probability, 4) if label == category else round(resto, 4)
    return scores