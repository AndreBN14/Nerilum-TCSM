from __future__ import annotations

from psycopg import Connection
from psycopg.rows import dict_row


def connect(dsn: str) -> Connection:
    conn = Connection.connect(dsn, row_factory=dict_row, autocommit=False)
    return conn
