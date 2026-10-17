from enum import Enum


class HistorySort(str, Enum):
    newest = "newest"
    oldest = "oldest"
    name_az = "nameAZ"
    probability = "probability"


def history_order_sql(sort: HistorySort) -> str:
    """Fragmentos cerrados: nunca concatenar un identificador recibido del cliente."""
    return {
        HistorySort.newest: "created_at DESC, id DESC",
        HistorySort.oldest: "created_at ASC, id ASC",
        HistorySort.name_az: (
            "CASE WHEN display_name IS NULL THEN 1 ELSE 0 END, "
            "LOWER(display_name) ASC, created_at DESC, id DESC"
        ),
        HistorySort.probability: (
            "CASE WHEN probability IS NULL THEN 1 ELSE 0 END, "
            "probability DESC, created_at DESC, id DESC"
        ),
    }[HistorySort(sort)]
