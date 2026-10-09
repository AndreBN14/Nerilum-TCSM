from app.core.config import Settings


def test_env_file_and_process_override(tmp_path, monkeypatch) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text("PORT=8100\nCORS_ORIGINS=[\"http://localhost:3000\"]\n")
    monkeypatch.setenv("PORT", "8200")
    settings = Settings(_env_file=env_file)
    assert settings.port == 8200
    assert settings.cors_origins == ["http://localhost:3000"]
