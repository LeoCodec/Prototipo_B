from __future__ import annotations

import os
import traceback
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from flask import current_app, render_template, request
from werkzeug.exceptions import HTTPException


def _log_path() -> Path:
    folder = Path(current_app.instance_path) / "logs"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "prototipo_b_errors.log"


def record_error(exc: Exception) -> str:
    error_id = f"ERR-{datetime.now():%Y%m%d-%H%M%S}-{uuid4().hex[:6].upper()}"

    content = (
        "\n" + "=" * 80 + "\n"
        f"{error_id}\n"
        f"Fecha: {datetime.now().isoformat(timespec='seconds')}\n"
        f"Ruta: {getattr(request, 'method', '?')} {getattr(request, 'path', '?')}\n"
        f"Tipo: {type(exc).__name__}\n"
        f"Mensaje: {exc}\n"
        f"Traceback:\n{traceback.format_exc()}\n"
    )

    with _log_path().open("a", encoding="utf-8") as fh:
        fh.write(content)

    return error_id


def install_error_handler(app):
    @app.errorhandler(Exception)
    def friendly_error(exc):
        if isinstance(exc, HTTPException):
            return exc

        error_id = record_error(exc)
        return render_template("error_friendly.html", error_id=error_id), 500
