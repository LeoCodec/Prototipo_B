from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from flask import current_app


def _log_dir() -> Path:
    folder = Path(current_app.instance_path) / "logs"
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def record_event(event_type: str, study_id: int | None = None, result: str = "ok") -> None:
    # No guardar nombres, domicilios, telefonos, ingresos ni texto OCR.
    payload = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "event_type": event_type,
        "study_id": study_id,
        "result": result,
    }

    path = _log_dir() / "activity.jsonl"
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, ensure_ascii=False) + "\n")
