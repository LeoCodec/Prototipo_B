from datetime import datetime
from ..extensions import db


class Study(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    folio = db.Column(db.String(40), unique=True, nullable=False)
    student_name = db.Column(db.String(180), default="")
    status = db.Column(db.String(40), default="BORRADOR")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    total_income = db.Column(db.Float, default=0.0)
    total_expenses = db.Column(db.Float, default=0.0)
    household_size = db.Column(db.Integer, default=1)
    final_fee = db.Column(db.Float, nullable=True)  # valoración manual autorizada

    images = db.relationship("StudyImage", backref="study", lazy=True, cascade="all, delete-orphan")


class StudyImage(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    study_id = db.Column(db.Integer, db.ForeignKey("study.id"), nullable=False)
    filename = db.Column(db.String(255), nullable=False)
    page_number = db.Column(db.Integer, default=1)
    blur_score = db.Column(db.Float, default=0.0)
    brightness_score = db.Column(db.Float, default=0.0)
    quality_status = db.Column(db.String(20), default="REVISAR")
    ocr_text = db.Column(db.Text, default="")
    confirmed_text = db.Column(db.Text, default="")
    ocr_error = db.Column(db.Text, default="")
