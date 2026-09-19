"""
app/auth.py

User registration, profile editing, credential changes, and JWT handling.
"""
import datetime
import re
import uuid

import jwt
from flask import Blueprint, current_app, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

from app.models import (
    delete_user_account,
    get_user_by_username,
    save_user,
    update_user,
    update_username_references,
)

auth_bp = Blueprint("auth", __name__)

_USERNAME_PATTERN = re.compile(r"^[a-z0-9_]{3,30}$")
_EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _session_version(user: dict) -> int:
    try:
        return int(user.get("session_version", 0))
    except (TypeError, ValueError):
        return 0


def _public_user(user: dict) -> dict:
    return {
        "id": user.get("id", ""),
        "username": user.get("username", ""),
        "display_name": user.get("display_name", ""),
        "email": user.get("email", ""),
        "home_region": user.get("home_region", ""),
        "avatar_url": user.get("avatar_url", ""),
        "preferences": user.get("preferences", []),
    }


def _normalize_username(value: object) -> str:
    return str(value or "").strip().lower()


def _validate_username(username: str) -> str | None:
    if not _USERNAME_PATTERN.fullmatch(username):
        return "Username must be 3–30 characters using letters, numbers, or underscores"
    return None


def _validate_email(email: str) -> str | None:
    if email and not _EMAIL_PATTERN.fullmatch(email):
        return "Enter a valid email address"
    if len(email) > 160:
        return "Email address is too long"
    return None


def _validate_password(password: object) -> str | None:
    if not isinstance(password, str) or len(password) < 8:
        return "Password must be at least 8 characters"
    return None


def _normalize_preferences(value: object) -> list[str] | None:
    if not isinstance(value, list):
        return None
    if any(not isinstance(preference, str) for preference in value):
        return None
    normalized = []
    for preference in value:
        entry = preference.strip().lower()
        if entry and entry not in normalized:
            normalized.append(entry)
    return normalized


def _issue_token(user: dict) -> str:
    return create_token(
        user.get("username", ""),
        current_app.config["SECRET_KEY"],
        _session_version(user),
    )


def create_token(username: str, secret: str, session_version: int = 0) -> str:
    """Return a signed JWT for *username* valid for 24 hours."""
    now = datetime.datetime.now(datetime.timezone.utc)
    payload = {
        "sub": username,
        "sv": session_version,
        "iat": now,
        "exp": now + datetime.timedelta(hours=24),
    }
    return jwt.encode(payload, secret, algorithm="HS256")


def decode_token(token: str, secret: str) -> dict:
    """Decode and verify *token*. Raises jwt.PyJWTError on failure."""
    return jwt.decode(token, secret, algorithms=["HS256"])


def get_current_user(request_obj) -> str | None:
    """Extract a valid JWT subject whose session version is still current."""
    auth_header = request_obj.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return None
    token = auth_header.split(" ", 1)[1]
    try:
        payload = decode_token(token, current_app.config["SECRET_KEY"])
        username = payload.get("sub")
        if not isinstance(username, str):
            return None
        user = get_user_by_username(username)
        if user is None:
            return None
        if _session_version(user) != int(payload.get("sv", 0)):
            return None
        return username
    except (jwt.PyJWTError, TypeError, ValueError):
        return None


@auth_bp.route("/api/auth/register", methods=["POST"])
def register():
    """Register a new user."""
    data = request.get_json(silent=True) or {}
    username = _normalize_username(data.get("username"))
    password = data.get("password", "")
    preferences = _normalize_preferences(data.get("preferences", []))

    username_error = _validate_username(username)
    if username_error:
        return jsonify({"error": username_error}), 400
    if not isinstance(password, str) or not password:
        return jsonify({"error": "username and password are required"}), 400
    password_error = _validate_password(password)
    if password_error:
        return jsonify({"error": password_error}), 400
    if preferences is None:
        return jsonify({"error": "preferences must be a list of text values"}), 400
    if get_user_by_username(username):
        return jsonify({"error": "username already exists"}), 409

    user = {
        "id": str(uuid.uuid4()),
        "username": username,
        "password_hash": generate_password_hash(password),
        "preferences": preferences,
        "display_name": "",
        "email": "",
        "home_region": "",
        "avatar_url": "",
        "session_version": 0,
    }
    save_user(user)
    return jsonify({"message": "user registered successfully", "username": username}), 201


@auth_bp.route("/api/auth/login", methods=["POST"])
def login():
    """Authenticate a user and return a JWT."""
    data = request.get_json(silent=True) or {}
    username = _normalize_username(data.get("username"))
    password = data.get("password", "")
    user = get_user_by_username(username)
    if not username or not isinstance(password, str) or not password:
        return jsonify({"error": "username and password are required"}), 400
    if not user or not check_password_hash(user["password_hash"], password):
        return jsonify({"error": "invalid credentials"}), 401

    return jsonify({"token": _issue_token(user)}), 200


@auth_bp.route("/api/auth/me", methods=["GET"])
def me():
    """Return the current user's public profile."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401
    user = get_user_by_username(username)
    if user is None:
        return jsonify({"error": "user not found"}), 404
    return jsonify(_public_user(user)), 200


@auth_bp.route("/api/auth/refresh", methods=["POST"])
def refresh_token():
    """Issue a replacement JWT for the current valid session."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401
    user = get_user_by_username(username)
    if user is None:
        return jsonify({"error": "user not found"}), 404
    return jsonify({"user": _public_user(user), "token": _issue_token(user)}), 200


@auth_bp.route("/api/auth/profile", methods=["PATCH"])
def update_profile():
    """Update public profile details and travel preferences."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    updates = {}
    for field in ("display_name", "home_region", "avatar_url"):
        if field in data:
            if not isinstance(data[field], str):
                return jsonify({"error": f"{field} must be text"}), 400
            if len(data[field].strip()) > 160:
                return jsonify({"error": f"{field} is too long"}), 400
            updates[field] = data[field].strip()

    if "email" in data:
        if not isinstance(data["email"], str):
            return jsonify({"error": "email must be text"}), 400
        email = data["email"].strip().lower()
        email_error = _validate_email(email)
        if email_error:
            return jsonify({"error": email_error}), 400
        updates["email"] = email

    if "preferences" in data:
        preferences = _normalize_preferences(data["preferences"])
        if preferences is None:
            return jsonify({"error": "preferences must be a list of text values"}), 400
        updates["preferences"] = preferences

    if not updates:
        return jsonify({"error": "no profile changes supplied"}), 400

    user = update_user(username, updates)
    if user is None:
        return jsonify({"error": "user not found"}), 404
    return jsonify(_public_user(user)), 200


@auth_bp.route("/api/auth/username", methods=["PATCH"])
def update_username():
    """Change username and preserve ownership/share references."""
    current_username = get_current_user(request)
    if current_username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    new_username = _normalize_username(data.get("username"))
    current_password = data.get("current_password", "")
    username_error = _validate_username(new_username)
    if username_error:
        return jsonify({"error": username_error}), 400
    if new_username == current_username:
        return jsonify({"error": "choose a different username"}), 400
    if get_user_by_username(new_username):
        return jsonify({"error": "username already exists"}), 409

    user = get_user_by_username(current_username)
    if (
        not isinstance(current_password, str)
        or not user
        or not check_password_hash(user["password_hash"], current_password)
    ):
        return jsonify({"error": "current password is incorrect"}), 401

    renamed = update_username_references(current_username, new_username)
    if renamed is None:
        return jsonify({"error": "user not found"}), 404
    renamed = update_user(
        new_username,
        {"session_version": _session_version(renamed) + 1},
    )
    return jsonify({"user": _public_user(renamed), "token": _issue_token(renamed)}), 200


@auth_bp.route("/api/auth/password", methods=["PATCH"])
def update_password():
    """Change password and invalidate all existing sessions."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    current_password = data.get("current_password", "")
    new_password = data.get("new_password", "")
    user = get_user_by_username(username)
    if (
        not isinstance(current_password, str)
        or not user
        or not check_password_hash(user["password_hash"], current_password)
    ):
        return jsonify({"error": "current password is incorrect"}), 401
    password_error = _validate_password(new_password)
    if password_error:
        return jsonify({"error": password_error}), 400
    if current_password == new_password:
        return jsonify({"error": "new password must be different"}), 400

    updated = update_user(
        username,
        {
            "password_hash": generate_password_hash(new_password),
            "session_version": _session_version(user) + 1,
        },
    )
    return jsonify({"user": _public_user(updated), "token": _issue_token(updated)}), 200


@auth_bp.route("/api/auth/sessions/revoke", methods=["POST"])
def revoke_other_sessions():
    """Invalidate all other tokens and issue a replacement for this device."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401
    user = get_user_by_username(username)
    updated = update_user(
        username,
        {"session_version": _session_version(user) + 1},
    )
    return jsonify({"user": _public_user(updated), "token": _issue_token(updated)}), 200


@auth_bp.route("/api/auth/account", methods=["DELETE"])
def delete_account():
    """Delete the user and all locally persisted account-owned data."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    current_password = data.get("current_password", "")
    user = get_user_by_username(username)
    if (
        not isinstance(current_password, str)
        or not user
        or not check_password_hash(user["password_hash"], current_password)
    ):
        return jsonify({"error": "current password is incorrect"}), 401
    if not delete_user_account(username):
        return jsonify({"error": "account not found"}), 404
    return "", 204
