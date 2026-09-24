"""
app/location.py

Live position sharing between travellers who are already in a group together.

The feature exists so a group can see where its members are on the map while
they are out together. That is genuinely useful and also genuinely sensitive,
so the rules are kept narrow and are enforced here rather than trusted to the
app:

  * Nothing is stored unless the traveller sends it. The app only sends while
    the user has sharing switched on, and switching it off calls DELETE.
  * Only one position is kept per person, replaced on every update, so no
    movement history exists to be read back.
  * Positions expire (see LOCATION_TTL_SECONDS). Someone who closes the app
    fades out on their own.
  * A position is visible only to people who share a group with its owner.
    There is no endpoint that returns everybody.

Routes
------
PUT    /api/me/location             Publish where I am now
GET    /api/me/location             Show me exactly what is stored about me
DELETE /api/me/location             Erase it and stop sharing
GET    /api/location/companions     Live positions of my group members
"""
import datetime

from flask import Blueprint, jsonify, request

from app.auth import get_current_user
from app.models import (
    LOCATION_TTL_SECONDS,
    delete_location,
    get_live_locations,
    get_location_for_user,
    get_rooms_for_user,
    get_user_by_username,
    save_location,
)

location_bp = Blueprint("location", __name__)

# A phone fix is good to a few metres. Anything claiming to be accurate to a
# fraction of a millimetre, or vaguer than a continent, is a bad reading rather
# than a useful one, so it is not worth storing.
MAX_ACCURACY_METRES = 100_000


@location_bp.before_request
def _check_json():
    # Authentication first, for the same reason as elsewhere in the app: an
    # anonymous caller should be told they are anonymous, not that their JSON
    # is malformed.
    if get_current_user(request) is None:
        return jsonify({"error": "authentication required"}), 401
    if request.method in ("POST", "PUT", "PATCH") and not isinstance(request.get_json(silent=True), dict):
        return jsonify({"error": "JSON object required"}), 400


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _coordinate(value: object, limit: float) -> float | None:
    """Return *value* as a coordinate within ±*limit*, or None if it is not one.

    Booleans are rejected explicitly. In Python ``True`` is an ``int``, so a
    plain numeric check would quietly accept ``{"latitude": true}`` and store
    a position one metre north of the equator.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    if number != number or number in (float("inf"), float("-inf")):
        return None
    if not -limit <= number <= limit:
        return None
    return number


def _public_view(record: dict, user: dict | None = None) -> dict:
    profile = user or {}
    username = record.get("username")
    return {
        "username": username,
        "display_name": profile.get("display_name") or username,
        "avatar_url": profile.get("avatar_url", "") or "",
        "latitude": record.get("latitude"),
        "longitude": record.get("longitude"),
        "accuracy": record.get("accuracy"),
        "updated_at": record.get("updated_at"),
    }


@location_bp.route("/api/me/location", methods=["PUT"])
def publish_location():
    username = get_current_user(request)
    payload = request.get_json(silent=True) or {}

    latitude = _coordinate(payload.get("latitude"), 90)
    longitude = _coordinate(payload.get("longitude"), 180)
    if latitude is None or longitude is None:
        return jsonify({"error": "latitude and longitude must be valid coordinates"}), 400

    accuracy = _coordinate(payload.get("accuracy"), MAX_ACCURACY_METRES)
    if accuracy is not None and accuracy < 0:
        accuracy = None

    record = save_location({
        "username": username,
        "latitude": latitude,
        "longitude": longitude,
        "accuracy": accuracy,
        "updated_at": _now(),
    })
    return jsonify({
        "location": _public_view(record),
        "expires_in_seconds": LOCATION_TTL_SECONDS,
    }), 200


@location_bp.route("/api/me/location", methods=["GET"])
def read_own_location():
    """Show the traveller precisely what the server holds about them.

    Sharing is easier to trust when you can check it, so this mirrors the
    stored record back rather than summarising it.
    """
    username = get_current_user(request)
    record = get_location_for_user(username)
    return jsonify({
        "location": _public_view(record) if record else None,
        "expires_in_seconds": LOCATION_TTL_SECONDS,
    }), 200


@location_bp.route("/api/me/location", methods=["DELETE"])
def erase_own_location():
    username = get_current_user(request)
    removed = delete_location(username)
    return jsonify({"removed": removed}), 200


@location_bp.route("/api/location/companions", methods=["GET"])
def companions():
    """Live positions of people who share at least one group with the viewer.

    Membership is recomputed from the rooms on every call, so leaving a group
    takes effect immediately: the next request simply stops returning those
    members.
    """
    username = get_current_user(request)

    visible: set[str] = set()
    for room in get_rooms_for_user(username):
        members = room.get("members")
        if isinstance(members, list):
            visible.update(m for m in members if isinstance(m, str))
    visible.discard(username)

    results = []
    for record in get_live_locations():
        owner = record.get("username")
        if owner not in visible:
            continue
        profile = get_user_by_username(owner) or {}
        results.append(_public_view(record, profile))

    results.sort(key=lambda item: item.get("updated_at") or "", reverse=True)
    return jsonify({"companions": results}), 200
