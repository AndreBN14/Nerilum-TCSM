import logging

from app.core.config import Settings


def _capture_nerilum(caplog):
    logger = logging.getLogger("nerilum")
    caplog.set_level(logging.WARNING, logger="nerilum")
    logger.addHandler(caplog.handler)
    return logger


def test_env_file_and_process_override(tmp_path, monkeypatch) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text("PORT=8100\nCORS_ORIGINS=[\"http://localhost:3000\"]\n")
    monkeypatch.setenv("PORT", "8200")
    settings = Settings(_env_file=env_file)
    assert settings.port == 8200
    assert settings.cors_origins == ["http://localhost:3000"]


def test_default_inference_settings_match_onnx_artifact() -> None:
    settings = Settings(_env_file=None)
    assert settings.model_dir is None
    assert settings.model_resize_mode == "center_crop"
    assert settings.model_softmax is False


def test_blank_seed_demo_account_id_is_unset(monkeypatch) -> None:
    # Copiar .env.example tal cual no debe impedir el arranque.
    monkeypatch.setenv("SEED_DEMO_ACCOUNT_ID", "")
    settings = Settings(_env_file=None)
    assert settings.seed_demo_account_id is None


def test_legacy_model_env_warns_with_names_but_not_values(monkeypatch, caplog) -> None:
    from app.core.config import warn_legacy_model_env

    monkeypatch.setenv("MODEL_PATH", "/ruta/secreta/modelo.onnx")
    monkeypatch.setenv("MODEL_VERSION", "v9-legacy")

    logger = _capture_nerilum(caplog)
    try:
        warn_legacy_model_env()
    finally:
        logger.removeHandler(caplog.handler)

    assert "MODEL_PATH" in caplog.text
    assert "MODEL_VERSION" in caplog.text
    assert "MODEL_DIR" in caplog.text
    assert "/ruta/secreta/modelo.onnx" not in caplog.text
    assert "v9-legacy" not in caplog.text


def test_legacy_model_env_is_silent_when_clean(monkeypatch, caplog) -> None:
    from app.core.config import LEGACY_MODEL_ENV_VARS, warn_legacy_model_env

    for name in LEGACY_MODEL_ENV_VARS:
        monkeypatch.delenv(name, raising=False)

    logger = _capture_nerilum(caplog)
    try:
        warn_legacy_model_env()
    finally:
        logger.removeHandler(caplog.handler)

    assert caplog.text == ""
