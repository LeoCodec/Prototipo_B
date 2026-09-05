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

    return app
