"""Identidad del usuario autenticado.

No se definen register/login/refresh/logout: esas operaciones pertenecen a
Supabase Auth. ``/auth/me`` solo refleja las claims ya verificadas del JWT.
"""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.security import AuthenticatedUser
from app.routes.dependencies import get_current_user
from app.schemas.account import Account, AccountResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/me", response_model=AccountResponse)
def me(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
) -> AccountResponse:
    return AccountResponse(account=Account(id=user.id, email=user.email))
