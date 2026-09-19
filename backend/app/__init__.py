"""
app/__init__.py

Flask application factory.
"""
import os
from flask import Flask
from flask_cors import CORS


def create_app():
    """Create and configure the Flask application."""
    app = Flask(__name__)

    app.config["SECRET_KEY"] = os.environ.get(
        "SECRET_KEY", "globetrotter-secret-change-in-prod"
    )

    CORS(app)

    from app.auth import auth_bp
    from app.chat import chat_bp
    from app.destinations import destinations_bp
    from app.profile import profile_bp
    from app.recommendations import recommendations_bp
    from app.itineraries import itineraries_bp
    from app.shares import shares_bp
    from app.social import social_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(destinations_bp)
    app.register_blueprint(recommendations_bp)
    app.register_blueprint(itineraries_bp)
    app.register_blueprint(shares_bp)
    app.register_blueprint(social_bp)
    app.register_blueprint(profile_bp)
    app.register_blueprint(chat_bp)

    @app.get("/healthz")
    def healthz():
        """Lightweight liveness probe used by Docker and the reverse proxy."""
        return {"status": "ok"}, 200

    return app
