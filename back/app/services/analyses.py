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
from app.core.history_sort import HistorySort, history_order_sql
from app.core.idempotency import require_same_request
from app.core.model_info import ModelInfo

DemoRecord = tuple[str, str, float]


def _format_utc(value: datetime) -> str:
    """Formato canónico del contrato: ISO-8601 UTC con segundos y ``Z``."""

    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _now_iso() -> str:
    return _format_utc(datetime.now(timezone.utc))


def _normalize_created_at(value: str) -> str:
    """Normaliza ``created_at`` a segundos UTC (quita microsegundos legacy).

    Las filas antiguas se guardaron con ``.%f``; al leerlas se normalizan para
    que el contrato sea estable. Si el valor no es interpretable se devuelve tal
    cual, de modo que la validación del schema lo haga visible.
    """

    text = value.strip()
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return text
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return _format_utc(parsed)


def _new_id() -> str:
    return f"an_{secrets.token_hex(6)}"


@dataclass
class AnalysisRecord:
    account_id: str
    category: str
    probability: float
    scores: dict[str, float]
    model_name: str
    model_version: str
    model_dataset: str
    display_name: str | None = None
    is_demo: bool = False
    id: str = field(default_factory=_new_id)
    created_at: str = field(default_factory=_now_iso)
    idempotency_key: str | None = None
    request_hash: str | None = None

    def __post_init__(self) -> None:
        if (self.idempotency_key is None) != (self.request_hash is None):
            raise ValueError("La clave de idempotencia y la huella deben existir juntas.")

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
            model_dataset=row["model_dataset"],
            created_at=_normalize_created_at(row["created_at"]),
            idempotency_key=row["idempotency_key"],
            request_hash=row["request_hash"],
        )


class AnalysisRepository(Protocol):
    def create(self, record: AnalysisRecord) -> AnalysisRecord: ...
    def list_by_account(
        self, account_id: str, *, limit: int, offset: int,
        sort: HistorySort = HistorySort.newest,
    ) -> tuple[list[AnalysisRecord], int]: ...
    def get_by_account(self, analysis_id: str, account_id: str) -> AnalysisRecord | None: ...
    def get_by_idempotency_key(
        self, account_id: str, key: str, request_hash: str
    ) -> AnalysisRecord | None: ...
    def ensure_schema(self) -> None: ...
    def seed_demo(self, account_id: str, model_info: ModelInfo) -> int: ...
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
                    model_dataset TEXT NOT NULL,
                    created_at    TEXT NOT NULL,
                    idempotency_key TEXT,
                    request_hash    TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_analyses_account_created
                    ON analyses (account_id, created_at DESC);
                """
            )
            # Actualización aditiva de SQLite local: preservar el historial existente.
            conn.execute("BEGIN IMMEDIATE")
            columns = {row["name"] for row in conn.execute("PRAGMA table_info(analyses)")}
            for column in ("idempotency_key", "request_hash"):
                if column not in columns:
                    conn.execute(f"ALTER TABLE analyses ADD COLUMN {column} TEXT")
            conn.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_analyses_account_idempotency "
                "ON analyses (account_id, idempotency_key)"
            )

    def create(self, record: AnalysisRecord) -> AnalysisRecord:
        with self._connect() as conn:
            for _ in range(3):
                try:
                    conn.execute(
                        """
                        INSERT INTO analyses (
                            id, account_id, category, probability, scores_json,
                            display_name, is_demo, model_name, model_version,
                            model_dataset, created_at, idempotency_key, request_hash
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                            record.model_dataset,
                            record.created_at,
                            record.idempotency_key,
                            record.request_hash,
                        ),
                    )
                    break
                except sqlite3.IntegrityError:
                    conn.rollback()
                    if record.idempotency_key is not None:
                        previous = self.get_by_idempotency_key(
                            record.account_id, record.idempotency_key, record.request_hash
                        )
                        if previous is not None:
                            return previous
                    record.id = _new_id()
            else:
                raise ApiException(500, "internal_error", "No se pudo guardar el análisis.")
            return record

    def list_by_account(
        self, account_id: str, *, limit: int, offset: int,
        sort: HistorySort = HistorySort.newest,
    ) -> tuple[list[AnalysisRecord], int]:
        order = history_order_sql(sort)
        with self._connect() as conn:
            total = conn.execute(
                "SELECT COUNT(*) FROM analyses WHERE account_id = ?",
                (account_id,),
            ).fetchone()[0]
            rows = conn.execute(
                f"""
                SELECT * FROM analyses
                WHERE account_id = ?
                ORDER BY {order}
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

    def seed_demo(self, account_id: str, model_info: ModelInfo) -> int:
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
                        display_name, is_demo, model_name, model_version,
                        model_dataset, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
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
        return len(demo)

    def get_by_idempotency_key(
        self, account_id: str, key: str, request_hash: str
    ) -> AnalysisRecord | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM analyses WHERE account_id = ? AND idempotency_key = ?",
                (account_id, key),
            ).fetchone()
        if row is None:
            return None
        require_same_request(row["request_hash"], request_hash)
        return AnalysisRecord.from_row(row)

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
