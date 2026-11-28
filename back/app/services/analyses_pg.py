from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

import psycopg
from psycopg import errors as pg_errors

from app.core.errors import ApiException
from app.core.history_sort import HistorySort, history_order_sql
from app.core.idempotency import require_same_request
from app.core.model_info import ModelInfo
from app.services.analyses import (
    AnalysisRecord,
    DemoRecord,
    _demo_scores,
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


class PostgresAnalysisRepository:
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
            migration = Path(__file__).resolve().parents[2] / "migrations" / "001_create_analyses.sql"
            conn.execute(migration.read_text(encoding="utf-8"))
            owner_type = conn.execute(
                "SELECT atttypid::regtype::text AS type FROM pg_attribute "
                "WHERE attrelid = 'analyses'::regclass AND attname = 'account_id'"
            ).fetchone()
            if owner_type["type"] != "uuid":
                # Guardar los permisos antes de exigir la migración de tipo.
                conn.commit()
                raise RuntimeError("Ejecuta migrations/002_secure_existing_analyses.sql para convertir account_id a UUID.")
            probability_type = conn.execute(
                "SELECT atttypid::regtype::text AS type FROM pg_attribute "
                "WHERE attrelid = 'analyses'::regclass AND attname = 'probability'"
            ).fetchone()
            if probability_type["type"] != "double precision":
                conn.commit()
                raise RuntimeError(
                    "Ejecuta migrations/003_align_probability_precision.sql para "
                    "actualizar probability y recuperar su valor desde scores_json."
                )
            idempotency_schema = conn.execute(
                "SELECT (SELECT COUNT(*) FROM pg_attribute "
                "WHERE attrelid = 'analyses'::regclass AND NOT attisdropped "
                "AND attname IN ('idempotency_key', 'request_hash')) = 2 "
                "AND EXISTS (SELECT 1 FROM pg_constraint "
                "WHERE conrelid = 'analyses'::regclass AND contype = 'u' "
                "AND conname = 'analyses_account_idempotency_key') AS ready"
            ).fetchone()
            if not idempotency_schema["ready"]:
                conn.commit()
                raise RuntimeError("Ejecuta migrations/004_analysis_idempotency.sql antes de arrancar.")
            conn.commit()

    def require_image_schema(self) -> None:
        with self._connect() as conn:
            columns = conn.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema = current_schema() AND table_name = 'analyses' "
                "AND column_name IN ('image_path', 'image_sha256', 'image_mime_type')"
            ).fetchall()
        if len(columns) != 3:
            raise RuntimeError("Ejecuta migrations/005_analysis_images.sql antes de habilitar imágenes.")

    def require_gradcam_schema(self) -> None:
        with self._connect() as conn:
            columns = conn.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema = current_schema() AND table_name = 'analyses' "
                "AND column_name IN ('grad_cam_path', 'grad_cam_sha256', 'grad_cam_mime_type')"
            ).fetchall()
        if len(columns) != 3:
            raise RuntimeError("Ejecuta migrations/006_analysis_grad_cam.sql antes de guardar mapas.")

    def list_image_paths(self) -> set[str]:
        with self._connect() as conn:
            return {row["image_path"] for row in conn.execute(
                "SELECT image_path FROM analyses WHERE image_path IS NOT NULL")}

    def create(self, record: AnalysisRecord) -> AnalysisRecord:
        with self._connect() as conn:
            for _ in range(3):
                try:
                    conn.execute(
                        """
                        INSERT INTO analyses (
                            id, account_id, category, probability, scores_json,
                            display_name, is_demo, model_name, model_version,
                            model_dataset, created_at, idempotency_key, request_hash,
                            image_path, image_sha256, image_mime_type,
                            grad_cam_path, grad_cam_sha256, grad_cam_mime_type
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        """,
                        (
                            record.id,
                            UUID(record.account_id),
                            record.category,
                            record.probability,
                            json.dumps(record.scores),
                            record.display_name,
                            bool(record.is_demo),
                            record.model_name,
                            record.model_version,
                            record.model_dataset,
                            record.created_at,
                            record.idempotency_key,
                            record.request_hash,
                            record.image_path,
                            record.image_sha256,
                            record.image_mime_type,
                            record.grad_cam_path,
                            record.grad_cam_sha256,
                            record.grad_cam_mime_type,
                        ),
                    )
                    conn.commit()
                    break
                except pg_errors.UniqueViolation:
                    conn.rollback()
                    if record.idempotency_key is not None:
                        previous = self.get_by_idempotency_key(
                            record.account_id, record.idempotency_key, record.request_hash
                        )
                        if previous is not None:
                            return previous
                    if record.fixed_id:
                        raise ApiException(409, "idempotency_conflict", "El análisis ya fue guardado con otra solicitud.") from None
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
            total_row = conn.execute(
                "SELECT COUNT(*) AS cnt FROM analyses WHERE account_id = %s",
                (UUID(account_id),),
            ).fetchone()
            total = int(total_row["cnt"]) if total_row else 0
            rows = conn.execute(
                f"""
                SELECT * FROM analyses
                WHERE account_id = %s
                ORDER BY {order}
                LIMIT %s OFFSET %s
                """,
                (UUID(account_id), limit, offset),
            ).fetchall()
            items = []
            for r in rows:
                item = AnalysisRecord(
                    id=r["id"],
                    account_id=str(r["account_id"]),
                    category=r["category"],
                    probability=float(r["probability"]),
                    scores=json.loads(r["scores_json"]) if isinstance(r["scores_json"], str) else r["scores_json"],
                    display_name=r["display_name"],
                    is_demo=bool(r["is_demo"]),
                    model_name=r["model_name"],
                    model_version=r["model_version"],
                    model_dataset=r["model_dataset"],
                    created_at=_pg_normalize_created_at(r["created_at"]),
                    idempotency_key=r["idempotency_key"],
                    request_hash=r["request_hash"],
                    image_path=r["image_path"],
                    image_sha256=r["image_sha256"],
                    image_mime_type=r["image_mime_type"],
                    grad_cam_path=r["grad_cam_path"],
                    grad_cam_sha256=r["grad_cam_sha256"],
                    grad_cam_mime_type=r["grad_cam_mime_type"],
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
                (analysis_id, UUID(account_id)),
            ).fetchone()
        if row is None:
            return None
        return AnalysisRecord(
            id=row["id"],
            account_id=str(row["account_id"]),
            category=row["category"],
            probability=float(row["probability"]),
            scores=json.loads(row["scores_json"]) if isinstance(row["scores_json"], str) else row["scores_json"],
            display_name=row["display_name"],
            is_demo=bool(row["is_demo"]),
            model_name=row["model_name"],
            model_version=row["model_version"],
            model_dataset=row["model_dataset"],
            created_at=_pg_normalize_created_at(row["created_at"]),
            idempotency_key=row["idempotency_key"],
            request_hash=row["request_hash"],
            image_path=row["image_path"],
            image_sha256=row["image_sha256"],
            image_mime_type=row["image_mime_type"],
            grad_cam_path=row["grad_cam_path"],
            grad_cam_sha256=row["grad_cam_sha256"],
            grad_cam_mime_type=row["grad_cam_mime_type"],
        )

    def get_by_idempotency_key(
        self, account_id: str, key: str, request_hash: str
    ) -> AnalysisRecord | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT id, request_hash FROM analyses "
                "WHERE account_id = %s AND idempotency_key = %s",
                (UUID(account_id), key),
            ).fetchone()
        if row is None:
            return None
        require_same_request(row["request_hash"], request_hash)
        return self.get_by_account(row["id"], account_id)

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
                (UUID(account_id),),
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
                        UUID(account_id),
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

    def delete_by_account(self, account_id: str) -> int:
        """Elimina todos los análisis de la cuenta. Devuelve filas borradas."""
        with self._connect() as conn:
            cursor = conn.execute(
                "DELETE FROM analyses WHERE account_id = %s",
                (UUID(account_id),),
            )
            conn.commit()
            return cursor.rowcount

    def close(self) -> None:
        pass
