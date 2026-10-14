from uuid import UUID

from pydantic import BaseModel


class Account(BaseModel):
    """Identidad derivada del JWT validado; no de una tabla local."""

    id: UUID
    email: str | None = None


class AccountResponse(BaseModel):
    account: Account
