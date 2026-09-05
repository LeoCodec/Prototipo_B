from pathlib import Path
from flask import Blueprint, current_app, render_template, request, redirect, url_for, flash, send_from_directory
from werkzeug.utils import secure_filename
from ..extensions import db
from ..models import Study, StudyImage
from ..services.image_service import analyze_quality
from ..services.ocr_service import extract_text

capture_bp = Blueprint("capture", __name__, url_prefix="/capture")


@capture_bp.route("/<int:study_id>/mobile", methods=["GET", "POST"])
def mobile_capture(study_id):
    study = Study.query.get_or_404(study_id)

    if request.method == "POST":
        file = request.files.get("document")
        if not file or not file.filename:
            flash("Selecciona o toma una fotografía.", "error")
            return redirect(request.url)

        next_page = max([x.page_number for x in study.images], default=0) + 1
        filename = secure_filename(file.filename) or f"page_{next_page}.jpg"
        filename = f"{study.folio}_{next_page}_{filename}"
        path = Path(current_app.config["UPLOAD_FOLDER"]) / filename
        file.save(path)

        quality = analyze_quality(path)
        text, ocr_error = extract_text(path)

        item = StudyImage(
            study_id=study.id,
            filename=filename,
            page_number=next_page,
            blur_score=quality["blur"],
            brightness_score=quality["brightness"],
            quality_status=quality["status"],
            ocr_text=text,
            ocr_error=ocr_error,
        )
        db.session.add(item)
        db.session.commit()
        flash("Página agregada. Revisa la calidad antes de continuar.", "success")
        return redirect(request.url)

    return render_template("capture_mobile.html", study=study)


@capture_bp.route("/<int:study_id>/delete/<int:image_id>", methods=["POST"])
def delete_image(study_id, image_id):
    study = Study.query.get_or_404(study_id)
    image = StudyImage.query.filter_by(id=image_id, study_id=study.id).first_or_404()
    path = Path(current_app.config["UPLOAD_FOLDER"]) / image.filename
    if path.exists():
        path.unlink()
    db.session.delete(image)
    db.session.commit()
    flash("Página eliminada. Puedes volver a tomarla.", "success")
    return redirect(url_for("capture.mobile_capture", study_id=study.id))


@capture_bp.route("/file/<path:filename>")
def uploaded_file(filename):
    """Sirve las imágenes capturadas para revisión dentro del piloto."""
    return send_from_directory(str(current_app.config["UPLOAD_FOLDER"]), filename)
