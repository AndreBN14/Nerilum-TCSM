"""Pruebas del verificador JWT/JWKS con claves EC y JWKS simulados."""

from __future__ import annotations

import asyncio
import json
import time

import jwt
import pytest
from conftest import (
    ISSUER,
    KID,
    OTHER_KID,
    SUBJECT,
    FakeClock,
    JWKSStub,
    build_verifier,
    public_jwk,
    sign_token,
)
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

from app.core.security import (
    AuthenticatedUser,
    InvalidTokenError,
    JWKSUnavailableError,
)


async def test_valid_token_returns_user(make_verifier, keypair):
    verifier = make_verifier()
    user = await verifier.verify(sign_token(keypair))
    assert isinstance(user, AuthenticatedUser)
    assert str(user.id) == SUBJECT
    assert user.email == "user@example.com"


async def test_valid_token_without_email_returns_null(make_verifier, keypair):
    verifier = make_verifier()
    user = await verifier.verify(sign_token(keypair, email=None))
    assert user.email is None


async def test_expired_token_rejected(make_verifier, keypair):
    verifier = make_verifier()
    token = sign_token(keypair, exp=int(time.time()) - 10)
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


async def test_future_nbf_rejected(make_verifier, keypair):
    verifier = make_verifier()
    token = sign_token(keypair, nbf=int(time.time()) + 3600)
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


async def test_default_leeway_is_zero(make_verifier, keypair):
    verifier = make_verifier()
    token = sign_token(keypair, exp=int(time.time()) - 1)
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


async def test_leeway_is_configurable(make_verifier, keypair):
    verifier = make_verifier(leeway=30)
    token = sign_token(keypair, exp=int(time.time()) - 5)
    user = await verifier.verify(token)
    assert str(user.id) == SUBJECT


async def test_bad_signature_rejected(make_verifier, keypair, other_keypair):
    verifier = make_verifier()
    token = sign_token(other_keypair, kid=KID)
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


async def test_non_es256_algorithm_rejected(make_verifier):
    verifier = make_verifier()
    payload = {
        "iss": ISSUER,
        "aud": "authenticated",
        "sub": SUBJECT,
        "exp": int(time.time()) + 3600,
        "iat": int(time.time()),
    }
    token = jwt.encode(
        payload,
        "a-secret-long-enough-for-hmac-sha256-use",
        algorithm="HS256",
        headers={"kid": KID, "alg": "HS256"},
    )
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


async def test_wrong_issuer_rejected(make_verifier, keypair):
    verifier = make_verifier()
    token = sign_token(keypair, iss="https://evil.example.com/auth/v1")
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


async def test_wrong_audience_rejected(make_verifier, keypair):
    verifier = make_verifier()
    token = sign_token(keypair, aud="anon")
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


@pytest.mark.parametrize("claim", ["exp", "iss", "aud", "sub"])
async def test_missing_required_claim_rejected(make_verifier, keypair, claim):
    verifier = make_verifier()
    token = sign_token(keypair, omit=(claim,))
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


async def test_invalid_sub_uuid_rejected(make_verifier, keypair):
    verifier = make_verifier()
    token = sign_token(keypair, sub="not-a-uuid")
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)


async def test_unconfigured_supabase_url_is_unavailable(make_verifier, keypair):
    verifier = make_verifier(supabase_url="", issuer=None)
    with pytest.raises(JWKSUnavailableError):
        await verifier.verify(sign_token(keypair))


async def test_jwks_fetched_once_and_cached(make_verifier, keypair, stub):
    verifier = make_verifier()
    token = sign_token(keypair)
    await verifier.verify(token)
    await verifier.verify(token)
    assert stub.calls == 1


async def test_cache_expiry_triggers_refetch(stub, keypair):
    clock = FakeClock()
    verifier = build_verifier(
        stub, cache_ttl=100, min_refresh_interval=0, clock=clock
    )
    try:
        await verifier.verify(sign_token(keypair))
        assert stub.calls == 1
        clock.advance(1000)
        await verifier.verify(sign_token(keypair))
        assert stub.calls == 2
    finally:
        await verifier.aclose()


async def test_unknown_kid_triggers_successful_refresh(stub, keypair, other_keypair):
    verifier = build_verifier(stub, min_refresh_interval=0)
    try:
        await verifier.verify(sign_token(keypair, kid=KID))
        assert stub.calls == 1
        stub.keys.append(public_jwk(other_keypair, OTHER_KID))
        user = await verifier.verify(sign_token(other_keypair, kid=OTHER_KID))
        assert str(user.id) == SUBJECT
        assert stub.calls == 2
    finally:
        await verifier.aclose()


async def test_unknown_kid_absent_after_refresh_is_invalid(
    make_verifier, keypair, other_keypair, stub
):
    verifier = make_verifier()
    token = sign_token(other_keypair, kid="ghost-kid")
    with pytest.raises(InvalidTokenError):
        await verifier.verify(token)
    assert stub.calls == 1


async def test_refresh_throttled_returns_unavailable(
    make_verifier, keypair, other_keypair, stub
):
    verifier = make_verifier(min_refresh_interval=60)
    await verifier.verify(sign_token(keypair))
    assert stub.calls == 1
    with pytest.raises(JWKSUnavailableError):
        await verifier.verify(sign_token(other_keypair, kid="new-kid"))
    assert stub.calls == 1


async def test_jwks_unavailable_without_cache(make_verifier, keypair, stub):
    verifier = make_verifier()
    stub.status = 500
    with pytest.raises(JWKSUnavailableError):
        await verifier.verify(sign_token(keypair))


async def test_jwks_unavailable_with_cached_key_still_verifies(
    make_verifier, keypair, stub
):
    verifier = make_verifier()
    token = sign_token(keypair)
    await verifier.verify(token)
    stub.status = 500
    user = await verifier.verify(token)
    assert str(user.id) == SUBJECT


async def test_jwks_bad_json_is_unavailable(make_verifier, keypair, stub):
    verifier = make_verifier()
    stub.raw = b"not-json"
    with pytest.raises(JWKSUnavailableError):
        await verifier.verify(sign_token(keypair))


async def test_jwks_malformed_structure_is_unavailable(make_verifier, keypair, stub):
    verifier = make_verifier()
    stub.raw = b'{"not_keys": []}'
    with pytest.raises(JWKSUnavailableError):
        await verifier.verify(sign_token(keypair))


async def test_incompatible_key_rejected(keypair):
    rsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = json.loads(RSAAlgorithm.to_jwk(rsa_key.public_key()))
    jwk["kid"] = "rsa-kid"
    stub = JWKSStub([jwk])
    verifier = build_verifier(stub)
    try:
        token = sign_token(keypair, kid="rsa-kid")
        with pytest.raises(InvalidTokenError):
            await verifier.verify(token)
    finally:
        await verifier.aclose()


async def test_concurrent_requests_do_not_refetch(stub, keypair):
    stub.keys.append(public_jwk(keypair, OTHER_KID))
    verifier = build_verifier(stub, min_refresh_interval=60)
    try:
        tokens = [verifier.verify(sign_token(keypair, kid=OTHER_KID)) for _ in range(10)]
        results = await asyncio.gather(*tokens)
        assert all(str(user.id) == SUBJECT for user in results)
        assert stub.calls == 1
    finally:
        await verifier.aclose()
