"""
app/itineraries.py

Create, read, update, and delete itineraries for the authenticated user.

Routes
------
POST /api/itineraries        – create a new itinerary
GET  /api/itineraries        – list all itineraries for the logged-in user
GET  /api/itineraries/<id>   – get a single itinerary
PUT  /api/itineraries/<id>   – update an itinerary
DELETE /api/itineraries/<id> – delete an itinerary
"""
import uuid
import datetime
from functools import wraps

from flask import Blueprint, request, jsonify

from app.auth import get_current_user
from app.models import (
    _WRITE_LOCK,
    get_shares_for_itinerary,
    delete_share,
    get_itineraries_for_user,
    save_itinerary,
    get_itinerary_by_id,
    update_itinerary,
    delete_itinerary,
)

itineraries_bp = Blueprint("itineraries", __name__)


def _locked(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        with _WRITE_LOCK:
            return function(*args, **kwargs)
    return wrapped


@itineraries_bp.before_request
def _check_json():
    if request.method in ("POST", "PUT", "PATCH") and not isinstance(request.get_json(silent=True), dict):
        return jsonify({"error": "JSON object required"}), 400


def _validate_trip(data: dict) -> str | None:
    for field, limit in (("title", 120), ("notes", 5000)):
        value = data.get(field, "")
        if not isinstance(value, str) or len(value) > limit:
            return f"{field} must be text of at most {limit} characters"
    if not data.get("title", "").strip():
        return "title is required"
    stops = data.get("destinations", [])
    if not isinstance(stops, list) or not 1 <= len(stops) <= 100:
        return "choose between 1 and 100 destinations"
    if any(not isinstance(s, str) or not s.strip() or s != s.strip() or len(s) > 200 for s in stops):
        return "destinations must be nonempty text values"
    if len(set(stops)) != len(stops):
        return "destinations must be unique"
    start, end = data.get("start_date", ""), data.get("end_date", "")
    if not isinstance(start, str) or not isinstance(end, str):
        return "dates must use YYYY-MM-DD"
    if start or end:
        try:
            first, last = datetime.date.fromisoformat(start), datetime.date.fromisoformat(end)
            if first.isoformat() != start or last.isoformat() != end:
                return "dates must use YYYY-MM-DD"
        except ValueError:
            return "provide both valid dates in YYYY-MM-DD format"
        if last < first:
            return "end_date must not precede start_date"
    visited = data.get("visited_stops", [])
    if (not isinstance(visited, list)
            or any(not isinstance(s, str) or s not in stops for s in visited)
            or len(set(visited)) != len(visited)):
        return "visited_stops must be unique destinations on this trip"
    return None


def _build_itinerary_response(itinerary: dict) -> dict:
    """Return a clean copy of the itinerary with created_at formatted."""
    entry = dict(itinerary)
    return entry


@itineraries_bp.route("/api/itineraries", methods=["POST"])
@_locked
def create_itinerary():
    """Create a new itinerary for the authenticated user.

    Expected JSON body:
        {
          "title": "Summer in Cameroon",
          "destinations": ["Kribi", "Mount Cameroon"],
          "start_date": "2025-06-01",
          "end_date": "2025-06-15",
          "notes": "Optional free-text notes"
        }

    Returns 201 with the created itinerary on success.
    Requires: Authorization: ******
    """
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    error = _validate_trip(data)
    if error:
        return jsonify({"error": error}), 400
    title = data.get("title", "").strip()
    destinations = data.get("destinations", [])

    if not title:
        return jsonify({"error": "title is required"}), 400

    if not isinstance(destinations, list):
        return jsonify({"error": "destinations must be a list"}), 400

    itinerary = {
        "id": str(uuid.uuid4()),
        "username": username,
        "title": title,
        "destinations": destinations,
        "start_date": data.get("start_date", ""),
        "end_date": data.get("end_date", ""),
        "notes": data.get("notes", ""),
        "visited_stops": [],
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    save_itinerary(itinerary)
    return jsonify(_build_itinerary_response(itinerary)), 201


@itineraries_bp.route("/api/itineraries", methods=["GET"])
def list_itineraries():
    """List all itineraries for the authenticated user.

    Returns 200 with a JSON array of itinerary objects.
    Requires: Authorization: ******
    """
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401

    itineraries = get_itineraries_for_user(username)
    return jsonify([_build_itinerary_response(it) for it in itineraries]), 200


@itineraries_bp.route("/api/itineraries/<itinerary_id>", methods=["GET"])
def get_itinerary(itinerary_id):
    """Get a single itinerary for the authenticated user."""
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401

    it = get_itinerary_by_id(itinerary_id)
    if not it:
        return jsonify({"error": "itinerary not found"}), 404

    if it.get("username") != username:
        return jsonify({"error": "forbidden"}), 403

    return jsonify(_build_itinerary_response(it)), 200


@itineraries_bp.route("/api/itineraries/<itinerary_id>", methods=["PUT"])
@_locked
def update_itinerary_route(itinerary_id):
    """Update an itinerary for the authenticated user.

    Allowed fields to update: title, destinations, start_date, end_date, notes.

    Requires: Authorization: ******
    """
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401

    it = get_itinerary_by_id(itinerary_id)
    if not it:
        return jsonify({"error": "itinerary not found"}), 404

    if it.get("username") != username:
        return jsonify({"error": "forbidden"}), 403

    data = request.get_json(silent=True) or {}
    allowed_fields = {"title", "destinations", "start_date", "end_date", "notes", "visited_stops"}
    updates = {k: v for k, v in data.items() if k in allowed_fields}
    if not updates:
        return jsonify({"error": "no itinerary changes supplied"}), 400
    if isinstance(updates.get("destinations"), list) and "visited_stops" not in updates:
        updates["visited_stops"] = [s for s in it.get("visited_stops", []) if s in updates["destinations"]]
    error = _validate_trip({**it, **updates})
    if error:
        return jsonify({"error": error}), 400
    if "title" in updates:
        updates["title"] = updates["title"].strip()

    updated = update_itinerary(itinerary_id, updates)
    if not updated:
        return jsonify({"error": "update failed"}), 500

    return jsonify(_build_itinerary_response(updated)), 200


@itineraries_bp.route("/api/itineraries/<itinerary_id>", methods=["DELETE"])
@_locked
def delete_itinerary_route(itinerary_id):
    """Delete an itinerary for the authenticated user.

    Requires: Authorization: ******
    """
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401

    it = get_itinerary_by_id(itinerary_id)
    if not it:
        return jsonify({"error": "itinerary not found"}), 404

    if it.get("username") != username:
        return jsonify({"error": "forbidden"}), 403

    deleted = delete_itinerary(itinerary_id)
    if not deleted:
        return jsonify({"error": "delete failed"}), 500

    for share in get_shares_for_itinerary(itinerary_id):
        delete_share(share["id"])
    return jsonify({"message": "itinerary deleted successfully"}), 200


@itineraries_bp.route("/api/itineraries/<itinerary_id>/visited", methods=["PUT"])
@_locked
def set_visited_stop(itinerary_id):
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401
    itinerary = get_itinerary_by_id(itinerary_id)
    if not itinerary:
        return jsonify({"error": "itinerary not found"}), 404
    if itinerary.get("username") != username:
        return jsonify({"error": "forbidden"}), 403
    data = request.get_json()
    stop, visited = data.get("destination"), data.get("visited")
    if not isinstance(stop, str) or stop not in itinerary.get("destinations", []) or type(visited) is not bool:
        return jsonify({"error": "provide a trip destination and a boolean visited value"}), 400
    stops = list(itinerary.get("visited_stops", []))
    if visited and stop not in stops:
        stops.append(stop)
    if not visited and stop in stops:
        stops.remove(stop)
    return jsonify(update_itinerary(itinerary_id, {"visited_stops": stops})), 200
