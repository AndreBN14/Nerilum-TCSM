"""Administración de usuarios de Supabase Auth (Admin API + service_role).

Solo el backend posee la ``service_role``; el portal web nunca la ve. Se usa
para eliminar la cuenta del usuario autenticado en ``DELETE /auth/me``: el id
proviente del JWT verificado, nunca del cuerpo de la petición.
"""

from __future__ import annotations

from urllib.parse import quote

import httpx

from app.core.errors import ApiException


class SupabaseAuthAdmin:
    """Cliente mínimo de GoTrue Admin: lo justo para eliminar la cuenta.

    Al eliminar el usuario, Supabase borra ``profiles`` por FK cascade y
    revoca sus sesiones (refresh tokens).
    """

    def __init__(
        self, url: str, service_role_key: str, client: httpx.Client | None = None
    ) -> None:
        if not url.startswith("https://") or not service_role_key:
            raise ValueError(
                "Admin API requiere URL HTTPS y service_role key"
            )
        self._root = f"{url.rstrip('/')}/auth/v1/admin"
        self._client = client or httpx.Client(timeout=30)
        self._client.headers.update(
            {
                "apikey": service_role_key,
                "Authorization": f"Bearer {service_role_key}",
            }
        )

    def delete_user(self, user_id: str) -> None:
        """Elimina el usuario. Un 404 se considera ya eliminado (idempotente)."""
        path = quote(user_id, safe="")
        try:
            response = self._client.delete(f"{self._root}/users/{path}")
        except httpx.HTTPError as exc:
            raise ApiException(
                503,
                "auth_admin_unavailable",
                "No se pudo completar la eliminación de la cuenta. "
                "Reintenta en unos segundos.",
            ) from exc
        if response.status_code in (200, 204, 404):
            return
        raise ApiException(
            503,
            "auth_admin_unavailable",
            "No se pudo completar la eliminación de la cuenta. "
            "Reintenta en unos segundos.",
        )

    def close(self) -> None:
        self._client.close()
