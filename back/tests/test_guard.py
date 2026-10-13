"""Verifica que la guardia de higiene de la suite falla cuando debe.

La guardia de sesión (`_project_db_guard` en ``conftest.py``) no debe fallar
nunca en una ejecución normal; aquí se ejercita su lógica con una ruta temporal
para confirmar que detecta la creación del archivo.
"""

from __future__ import annotations

import os

import pytest

from conftest import _db_state, assert_project_db_untouched


def test_guard_detects_created_db(tmp_path) -> None:
    path = tmp_path / "nerilum.db"
    before = _db_state(path)
    path.write_text("creado por el test")
    after = _db_state(path)

    with pytest.raises(AssertionError, match="GUARDIA DE HIGIENE"):
        assert_project_db_untouched(before, after, path)


def test_guard_detects_modified_db(tmp_path) -> None:
    path = tmp_path / "nerilum.db"
    path.write_text("contenido")
    before = _db_state(path)

    # Fuerza un mtime distinto para no depender de la resolución del FS.
    os.utime(path, ns=(before + 10**9, before + 10**9))
    after = _db_state(path)
    assert after != before

    with pytest.raises(AssertionError, match="GUARDIA DE HIGIENE"):
        assert_project_db_untouched(before, after, path)


def test_guard_passes_when_untouched(tmp_path) -> None:
    path = tmp_path / "nerilum.db"
    assert_project_db_untouched(_db_state(path), _db_state(path), path)
