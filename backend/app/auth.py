"""
app/auth.py

User registration, profile editing, credential changes, and JWT handling.
"""
import datetime
import re
import secrets
import uuid
import os

import jwt
from flask import Blueprint, current_app, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

from app.models import (
    _WRITE_LOCK,
    delete_user_account,
    get_all_users,
    get_user_by_username,
    peek_password_reset,
    pop_password_reset,
    save_password_reset,
    save_user,
    update_user,
    update_username_references,
)

auth_bp = Blueprint("auth", __name__)

_USERNAME_PATTERN = re.compile(r"^[a-z0-9_]{3,30}$")
_EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

# A reset code is a short-lived second factor, not a password. Six digits is
# enough given the short window and the single-use rule below.
RESET_CODE_TTL_MINUTES = 15
RESET_MAX_ATTEMPTS = 5


@auth_bp.before_request
def _check_json_object():
    if request.endpoint in {
        "auth.register", "auth.login", "auth.update_profile", "auth.update_username",
        "auth.update_password", "auth.delete_account",
    } and not isinstance(request.get_json(silent=True), dict):
        return jsonify({"error": "JSON object required"}), 400


def _validate_avatar(value) -> str | None:
    """Only local image identifiers, never tracking URLs or path traversal."""
    if not isinstance(value, str):
        return "avatar_url must be text"
    if not value:
        return None
    if not re.fullmatch(r"/api/media/[0-9a-f]{32}\.(jpg|jpeg|png|gif|webp)", value):
        return "avatar must be an uploaded image"
    from app import models
    if not os.path.isfile(os.path.join(models.MEDIA_DIR, value.rsplit("/", 1)[-1])):
        return "uploaded image not found"
    return None


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
        "bio": user.get("bio", ""),
        "joined_at": user.get("created_at", ""),
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
        "bio": "",
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
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

    if "avatar_url" in updates:
        error = _validate_avatar(updates["avatar_url"])
        if error:
            return jsonify({"error": error}), 400
    if "bio" in data:
        if not isinstance(data["bio"], str) or len(data["bio"].strip()) > 280:
            return jsonify({"error": "bio must be text of at most 280 characters"}), 400
        updates["bio"] = data["bio"].strip()

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

    with _WRITE_LOCK:
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


def _find_by_identifier(identifier: str) -> dict | None:
    """Resolve a username or an email address to a user."""
    identifier = identifier.strip().lower()
    if not identifier:
        return None
    user = get_user_by_username(identifier)
    if user is not None:
        return user
    for candidate in get_all_users():
        if (candidate.get("email", "") or "").strip().lower() == identifier:
            return candidate
    return None


@auth_bp.route("/api/auth/request-password-reset", methods=["POST"])
def request_password_reset():
    """Issue a single-use reset code for an account.

    The response is identical whether or not the account exists. Saying "no
    such user" would turn this endpoint into a way to enumerate who has an
    account, which is worth more to an attacker than the convenience is worth
    to a legitimate user.

    There is no mail server on this deployment, so the code is returned in the
    response body. That is honest about what the feature currently is: a
    self-service reset for a user who still has their session, not a recovery
    path for a locked-out one. Wiring an SMTP provider in later changes only
    this function.
    """
    data = request.get_json(silent=True) or {}
    identifier = str(data.get("identifier", "") or "")
    user = _find_by_identifier(identifier)

    generic = {
        "message": "If that account exists, a reset code has been issued.",
    }

    if user is None:
        return jsonify(generic), 200

    code = f"{secrets.randbelow(1_000_000):06d}"
    expires = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(
        minutes=RESET_CODE_TTL_MINUTES
    )
    save_password_reset({
        "username": user.get("username"),
        # Stored hashed: a leaked data file should not hand over live codes.
        "code_hash": generate_password_hash(code),
        "expires_at": expires.isoformat(),
        "attempts": 0,
    })

    return jsonify({**generic, "code": code, "delivery": "in-response"}), 200


@auth_bp.route("/api/auth/reset-password", methods=["POST"])
def reset_password():
    """Consume a reset code and set a new password."""
    data = request.get_json(silent=True) or {}
    identifier = str(data.get("identifier", "") or "")
    code = str(data.get("code", "") or "").strip()
    new_password = data.get("new_password", "")

    invalid = jsonify({"error": "that code is not valid or has expired"}), 400

    user = _find_by_identifier(identifier)
    if user is None or not code:
        return invalid

    username = user.get("username", "")
    entry = peek_password_reset(username)
    if entry is None:
        return invalid

    expires_at = entry.get("expires_at", "")
    try:
        expired = datetime.datetime.fromisoformat(expires_at) < datetime.datetime.now(
            datetime.timezone.utc
        )
    except (TypeError, ValueError):
        expired = True
    if expired:
        pop_password_reset(username)
        return invalid

    # Guessing a six-digit code is only infeasible if the attempts are capped.
    attempts = int(entry.get("attempts", 0) or 0)
    if attempts >= RESET_MAX_ATTEMPTS:
        pop_password_reset(username)
        return invalid

    if not check_password_hash(entry.get("code_hash", ""), code):
        save_password_reset({**entry, "attempts": attempts + 1})
        return invalid

    password_error = _validate_password(new_password)
    if password_error:
        return jsonify({"error": password_error}), 400

    pop_password_reset(username)
    with _WRITE_LOCK:
        current = get_user_by_username(username)
        if current is None:
            return invalid
        update_user(username, {
            "password_hash": generate_password_hash(new_password),
            # Invalidate every existing session: if the account was taken over,
            # a reset has to evict the intruder, not just add a second holder.
            "session_version": _session_version(current) + 1,
        })

    return jsonify({"message": "Password updated. You can now sign in."}), 200
