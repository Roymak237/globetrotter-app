"""
app/profile.py

Everything hanging off the signed-in user: the interests that drive the
personalised feed, the notification inbox, and destinations the community
submits for review.

Routes
------
GET    /api/me/interests        Read the viewer's interest tags
PUT    /api/me/interests        Replace the viewer's interest tags
GET    /api/me/notifications    List the notification inbox
POST   /api/me/notifications/read  Mark some, or all, notifications read
GET    /api/me/submissions      List the viewer's own submissions
POST   /api/destinations/submit Suggest a new destination
PUT    /api/me/avatar           Set or clear the profile photo
PUT    /api/me/bio              Set or clear the public bio
GET    /api/users/<username>    Another traveller's public profile
"""
import datetime
import uuid
import math

from flask import Blueprint, jsonify, request

from app.auth import get_current_user, _validate_avatar
from app.models import (
    _WRITE_LOCK,
    get_all_destinations,
    get_notifications_for_user,
    get_submissions_for_user,
    get_user_by_username,
    mark_notifications_read,
    save_submission,
    update_user,
)

profile_bp = Blueprint("profile", __name__)

MAX_INTERESTS = 12
MAX_NAME_LENGTH = 120
MAX_DESCRIPTION_LENGTH = 2000
MAX_BIO_LENGTH = 280


@profile_bp.before_request
def _check_json():
    # Authentication is settled before the payload is inspected. Reversing the
    # two would answer an anonymous request with "your JSON is malformed",
    # which tells the caller nothing about the actual problem.
    if get_current_user(request) is None:
        return jsonify({"error": "authentication required"}), 401
    if request.method in ("POST", "PUT", "PATCH") and not isinstance(request.get_json(silent=True), dict):
        return jsonify({"error": "JSON object required"}), 400


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _safe_link(value: object) -> bool:
    """True when a submitted URL is an ordinary web link.

    Submitted URLs are rendered back to other travellers, so anything other
    than http or https is rejected outright. That closes off javascript: and
    data: payloads without needing to sanitise them later.
    """
    if not isinstance(value, str):
        return False
    return value.strip().lower().startswith(("http://", "https://"))


def available_interests() -> list:
    """Derive the interest vocabulary from the catalogue itself.

    Keeping this computed rather than hard-coded means a new destination
    category shows up as a choosable interest without a code change.
    """
    tags: set = set()
    for destination in get_all_destinations():
        category = str(destination.get("category", "") or "").strip()
        if category:
            tags.add(category)
        for tag in destination.get("tags", []) or []:
            tag = str(tag or "").strip()
            if tag:
                tags.add(tag)
    return sorted(tags)


@profile_bp.route("/api/me/interests", methods=["GET"])
def get_interests():
    """Return the viewer's interests alongside the full vocabulary."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    user = get_user_by_username(username) or {}
    return jsonify({
        "interests": user.get("preferences", []) or [],
        "available": available_interests(),
    }), 200


@profile_bp.route("/api/me/interests", methods=["PUT"])
def set_interests():
    """Replace the viewer's interests with the supplied list."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    raw = data.get("interests")
    if not isinstance(raw, list) or any(not isinstance(s, str) or len(s) > 80 for s in raw):
        return jsonify({"error": "interests must be a list"}), 400

    # De-duplicate while preserving the order the user picked them in.
    seen: set = set()
    interests: list = []
    for item in raw:
        tag = str(item or "").strip()
        if tag and tag.lower() not in seen:
            seen.add(tag.lower())
            interests.append(tag)

    if len(interests) > MAX_INTERESTS:
        return jsonify(
            {"error": f"choose at most {MAX_INTERESTS} interests"}
        ), 400

    with _WRITE_LOCK:
        update_user(username, {"preferences": interests})
    return jsonify({"interests": interests}), 200


@profile_bp.route("/api/me/notifications", methods=["GET"])
def list_notifications():
    """Return the inbox newest first, with the unread count."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    notifications = sorted(
        get_notifications_for_user(username),
        key=lambda n: n.get("created_at", ""),
        reverse=True,
    )
    unread = sum(1 for n in notifications if not n.get("read"))
    return jsonify({
        "unread": unread,
        "notifications": notifications,
    }), 200


@profile_bp.route("/api/me/notifications/read", methods=["POST"])
def read_notifications():
    """Mark the listed notifications read, or all of them when none given."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    ids = data.get("ids")
    if ids is not None and (not isinstance(ids, list) or any(not isinstance(s, str) for s in ids)):
        return jsonify({"error": "ids must be a list"}), 400

    changed = mark_notifications_read(username, ids)
    return jsonify({"marked_read": changed}), 200


@profile_bp.route("/api/me/submissions", methods=["GET"])
def list_my_submissions():
    """Return the viewer's submissions, newest first."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    submissions = sorted(
        get_submissions_for_user(username),
        key=lambda s: s.get("created_at", ""),
        reverse=True,
    )
    return jsonify(submissions), 200


@profile_bp.route("/api/destinations/submit", methods=["POST"])
def submit_destination():
    """Record a community suggestion for a new destination.

    Submissions land in a pending queue rather than the live catalogue, so a
    bad entry can never affect what other travellers see.
    """
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    for field, limit in (("name", 120), ("description", 2000), ("category", 80), ("address", 500), ("image_url", 500)):
        value = data.get(field, "")
        if not isinstance(value, str) or len(value) > limit:
            return jsonify({"error": f"{field} must be text of at most {limit} characters"}), 400
    if data.get("image_url") and not _safe_link(data["image_url"]):
        return jsonify({"error": "image_url must use http or https"}), 400
    name = str(data.get("name", "") or "").strip()
    if not name:
        return jsonify({"error": "name is required"}), 400
    if len(name) > MAX_NAME_LENGTH:
        return jsonify(
            {"error": f"name must be {MAX_NAME_LENGTH} characters or fewer"}
        ), 400

    description = str(data.get("description", "") or "").strip()
    if len(description) > MAX_DESCRIPTION_LENGTH:
        return jsonify(
            {"error": f"description must be {MAX_DESCRIPTION_LENGTH} characters or fewer"}
        ), 400

    latitude = data.get("latitude")
    longitude = data.get("longitude")
    if (latitude is None) != (longitude is None):
        return jsonify({"error": "provide both latitude and longitude"}), 400
    if latitude is not None and longitude is not None:
        if isinstance(latitude, bool) or isinstance(longitude, bool):
            return jsonify({"error": "coordinates must be numbers"}), 400
        try:
            latitude = float(latitude)
            longitude = float(longitude)
        except (TypeError, ValueError):
            return jsonify({"error": "latitude and longitude must be numbers"}), 400
        if not math.isfinite(latitude) or not math.isfinite(longitude) or not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
            return jsonify({"error": "latitude or longitude is out of range"}), 400
    else:
        latitude = longitude = None

    submission = {
        "id": str(uuid.uuid4()),
        "username": username,
        "name": name,
        "category": str(data.get("category", "") or "").strip(),
        "description": description,
        "address": str(data.get("address", "") or "").strip(),
        "image_url": str(data.get("image_url", "") or "").strip(),
        "latitude": latitude,
        "longitude": longitude,
        "status": "pending",
        "created_at": _now(),
        "reviewed_at": None,
    }
    save_submission(submission)
    return jsonify(submission), 201


@profile_bp.route("/api/me/avatar", methods=["PUT"])
def set_avatar():
    """Point the profile photo at an uploaded image, or clear it."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    avatar_url = data.get("avatar_url", "")
    # Restricted to our own media endpoint so a profile cannot be used to
    # embed a remote tracking pixel that fires for everyone who sees it.
    error = _validate_avatar(avatar_url)
    if error:
        return jsonify({"error": error}), 400

    with _WRITE_LOCK:
        updated = update_user(username, {"avatar_url": avatar_url})
    if updated is None:
        return jsonify({"error": "user not found"}), 404
    return jsonify({"avatar_url": avatar_url}), 200


@profile_bp.route("/api/me/bio", methods=["PUT"])
def set_bio():
    """Set the short public description shown on the profile."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    if not isinstance(data.get("bio", ""), str):
        return jsonify({"error": "bio must be text"}), 400
    bio = data.get("bio", "").strip()
    if len(bio) > MAX_BIO_LENGTH:
        return jsonify(
            {"error": f"bio must be {MAX_BIO_LENGTH} characters or fewer"}
        ), 400

    with _WRITE_LOCK:
        updated = update_user(username, {"bio": bio})
    if updated is None:
        return jsonify({"error": "user not found"}), 404
    return jsonify({"bio": bio}), 200


@profile_bp.route("/api/users/<target>", methods=["GET"])
def public_profile(target: str):
    """The public view of another traveller.

    Deliberately narrow: name, photo, bio and join date only. Email, interests
    and saved trips stay private, since nothing in the app needs them to be
    visible to strangers.
    """
    if get_current_user(request) is None:
        return jsonify({"error": "authentication required"}), 401

    user = get_user_by_username(target.strip().lower())
    if user is None:
        return jsonify({"error": "user not found"}), 404

    return jsonify({
        "username": user.get("username"),
        "display_name": user.get("display_name") or user.get("username"),
        "avatar_url": user.get("avatar_url", "") or "",
        "bio": user.get("bio", "") or "",
        "home_region": user.get("home_region", "") or "",
        "joined_at": user.get("created_at", ""),
    }), 200
