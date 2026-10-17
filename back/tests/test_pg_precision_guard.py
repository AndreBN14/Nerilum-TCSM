"""La aplicación no sigue escribiendo si aún queda el esquema float32."""

from unittest.mock import MagicMock

import pytest

from app.services.analyses_pg import PostgresAnalysisRepository


@pytest.mark.parametrize("column_type", ["real", "double precision"])
def test_pg_startup_requires_precision_migration(monkeypatch, column_type):
    connection = MagicMock()
    connection.__enter__.return_value = connection
    owner = MagicMock()
    owner.fetchone.return_value = {"type": "uuid"}
    probability = MagicMock()
    probability.fetchone.return_value = {"type": column_type}
    idempotency = MagicMock()
    idempotency.fetchone.return_value = {"ready": True}
    connection.execute.side_effect = [MagicMock(), owner, probability, idempotency]
    monkeypatch.setattr(PostgresAnalysisRepository, "_connect", lambda _: connection)

    if column_type == "real":
        with pytest.raises(RuntimeError, match="003_align_probability_precision"):
            PostgresAnalysisRepository("unused-test-dsn")
    else:
        PostgresAnalysisRepository("unused-test-dsn")
    connection.commit.assert_called_once()


def test_pg_startup_requires_idempotency_migration(monkeypatch):
    connection = MagicMock()
    connection.__enter__.return_value = connection
    results = [MagicMock() for _ in range(3)]
    for result, value in zip(results, [
        {"type": "uuid"}, {"type": "double precision"}, {"ready": False},
    ]):
        result.fetchone.return_value = value
    connection.execute.side_effect = [MagicMock(), *results]
    monkeypatch.setattr(PostgresAnalysisRepository, "_connect", lambda _: connection)
    with pytest.raises(RuntimeError, match="004_analysis_idempotency"):
        PostgresAnalysisRepository("unused-test-dsn")
