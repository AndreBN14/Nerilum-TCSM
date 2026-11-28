"""Identidad del usuario autenticado.

No se definen register/login/refresh/logout: esas operaciones pertenecen a
Supabase Auth. ``/auth/me`` solo refleja las claims ya verificadas del JWT.

``DELETE /auth/me`` elimina definitivamente la cuenta y todos sus datos.
El id proviene del JWT verificado; nunca del cuerpo de la petición.
"""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, Response
from starlette.concurrency import run_in_threadpool

from app.core.errors import ApiException
from app.core.security import AuthenticatedUser
from app.routes.dependencies import get_current_user, get_services
from app.schemas.account import Account, AccountResponse
from app.schemas.error import COMMON_ERRORS
from app.services.container import Services

logger = logging.getLogger("nerilum")

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/me", response_model=AccountResponse, responses=COMMON_ERRORS)
def me(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
) -> AccountResponse:
    return AccountResponse(account=Account(id=user.id, email=user.email))


@router.delete("/me", status_code=204, responses=COMMON_ERRORS)
async def delete_me(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
) -> Response:
    """Elimina definitivamente la cuenta autenticada y todos sus datos.

    Orden seguro: filas de analyses (sin FK a auth.users, el borrado es
    explícito) → carpeta de Storage del usuario (best-effort; los huérfanos
    los limpia el script de reconciliación) → usuario de Supabase Auth al
    final, que borra ``profiles`` por FK cascade y revoca las sesiones.
    """
    account_id = str(user.id)
    if services.auth_admin is None:
        raise ApiException(
            503,
            "account_deletion_unavailable",
            "La eliminación de cuenta no está disponible: el backend no "
            "tiene configurada la clave de servicio.",
        )

    deleted_rows = await run_in_threadpool(
        services.analyses.delete_by_account, account_id
    )
    logger.info(
        "delete_me: %s filas de análisis borradas para %s", deleted_rows, account_id
    )

    if services.image_storage is not None:
        try:
            await run_in_threadpool(
                services.image_storage.remove, f"{account_id}/"
            )
        except ApiException as exc:
            # Best-effort: un fallo de Storage no cancela la eliminación.
            logger.warning(
                "delete_me: no se pudo limpiar Storage de %s: %s",
                account_id,
                exc.detail,
            )

    await run_in_threadpool(services.auth_admin.delete_user, account_id)
    logger.info("delete_me: cuenta eliminada: %s", account_id)
    return Response(status_code=204)
