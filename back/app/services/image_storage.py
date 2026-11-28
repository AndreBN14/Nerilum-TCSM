"""Acceso servidor a los originales del bucket privado de Supabase Storage."""

from __future__ import annotations

import hashlib
from typing import Protocol
from urllib.parse import quote

import httpx

from app.core.errors import ApiException


class ImageStorage(Protocol):
    def put(self, path: str, content: bytes, mime_type: str) -> None: ...
    def get(self, path: str) -> bytes: ...
    def remove(self, path_or_prefix: str) -> None: ...
    def close(self) -> None: ...


class SupabaseImageStorage:
    def __init__(self, url: str, key: str, bucket: str = "analysis-images",
                 client: httpx.Client | None = None) -> None:
        if not url.startswith("https://") or not key or not bucket:
            raise ValueError("Storage requiere URL HTTPS, credencial privada y bucket")
        self._root = f"{url.rstrip('/')}/storage/v1"
        self._bucket = quote(bucket, safe='')
        self._base = f"{self._root}/object/{self._bucket}"
        self._client = client or httpx.Client(timeout=30)
        self._client.headers.update({"apikey": key, "Authorization": f"Bearer {key}"})

    def _url(self, path: str) -> str:
        return f"{self._base}/{quote(path, safe='/')}"

    def get(self, path: str) -> bytes:
        try:
            response = self._client.get(self._url(path))
        except httpx.HTTPError as exc:
            raise ApiException(503, "storage_unavailable", "No se pudo consultar la imagen almacenada.") from exc
        if response.status_code == 404:
            raise ApiException(404, "not_found", "Imagen no encontrada.")
        if response.status_code != 200:
            raise ApiException(503, "storage_unavailable", "No se pudo consultar la imagen almacenada.")
        return response.content

    def put(self, path: str, content: bytes, mime_type: str) -> None:
        try:
            response = self._client.post(
                self._url(path), content=content,
                headers={"Content-Type": mime_type, "x-upsert": "false"},
            )
        except httpx.HTTPError as exc:
            # La respuesta pudo perderse después de subir: el mismo path se
            # recupera en el reintento, sin sobrescribir objetos existentes.
            raise ApiException(503, "storage_unavailable", "No se pudo guardar la imagen.") from exc
        if response.status_code == 409:
            existing = self.get(path)
            if hashlib.sha256(existing).digest() == hashlib.sha256(content).digest():
                return
            raise ApiException(409, "idempotency_conflict", "El archivo ya existe con otro contenido.")
        if response.status_code not in (200, 201):
            raise ApiException(503, "storage_unavailable", "No se pudo guardar la imagen.")

    def close(self) -> None:
        self._client.close()

    def list(self, prefix: str = "", *, limit: int = 100, offset: int = 0) -> list[dict]:
        try:
            response = self._client.post(
                f"{self._root}/object/list/{self._bucket}",
                json={"prefix": prefix, "limit": limit, "offset": offset},
            )
        except httpx.HTTPError as exc:
            raise ApiException(503, "storage_unavailable", "No se pudo listar el bucket.") from exc
        if response.status_code != 200:
            raise ApiException(503, "storage_unavailable", "No se pudo listar el bucket.")
        return response.json()

    def remove(self, path_or_prefix: str) -> None:
        """Borra un objeto o, con un prefijo terminado en '/', toda su carpeta.

        Usado por la reconciliación de huérfanos y por DELETE /auth/me,
        que borra la carpeta completa del usuario con ``f"{account_id}/"``.
        """
        try:
            response = self._client.request("DELETE", self._base,
                                            json={"prefixes": [path_or_prefix]})
        except httpx.HTTPError as exc:
            raise ApiException(503, "storage_unavailable", "No se pudo borrar el archivo huérfano.") from exc
        if response.status_code not in (200, 204):
            raise ApiException(503, "storage_unavailable", "No se pudo borrar el archivo huérfano.")
