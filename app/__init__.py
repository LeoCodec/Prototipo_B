from pathlib import Path
from flask import Flask
from config import Config
from .extensions import db


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    Path(app.config["UPLOAD_FOLDER"]).mkdir(parents=True, exist_ok=True)
    Path(app.config["EXPORT_FOLDER"]).mkdir(parents=True, exist_ok=True)
    Path("instance").mkdir(parents=True, exist_ok=True)

    db.init_app(app)

    from .routes.main import main_bp
    from .routes.capture import capture_bp
    from .routes.review import review_bp
    from .routes.export import export_bp

    app.register_blueprint(main_bp)
    app.register_blueprint(capture_bp)
    app.register_blueprint(review_bp)
    app.register_blueprint(export_bp)

    with app.app_context():
        db.create_all()

    from app.routes.fields import fields_bp
    app.register_blueprint(fields_bp)

    from app.routes.analysis import analysis_bp
    app.register_blueprint(analysis_bp)

    from app.routes.export_v2 import export_v2_bp
    app.register_blueprint(export_v2_bp)

    from app.routes.review_fields import review_fields_bp, diagnostics_bp
    app.register_blueprint(review_fields_bp)
    app.register_blueprint(diagnostics_bp)

    from app.services.error_service import install_error_handler
    install_error_handler(app)

    from app.routes.reports import reports_bp
    app.register_blueprint(reports_bp)

    from app.routes.case_management import case_management_bp
    app.register_blueprint(case_management_bp)

    from app.services.security_service import auth_bp, install_security
    app.register_blueprint(auth_bp)
    install_security(app)

    from app.routes.institutional_forms import institutional_bp
    app.register_blueprint(institutional_bp)

    return app
