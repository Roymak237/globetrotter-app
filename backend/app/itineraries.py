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

from flask import Blueprint, request, jsonify

from app.auth import get_current_user
from app.models import (
    get_itineraries_for_user,
    save_itinerary,
    get_itinerary_by_id,
    update_itinerary,
    delete_itinerary,
)

itineraries_bp = Blueprint("itineraries", __name__)


def _build_itinerary_response(itinerary: dict) -> dict:
    """Return a clean copy of the itinerary with created_at formatted."""
    entry = dict(itinerary)
    return entry


@itineraries_bp.route("/api/itineraries", methods=["POST"])
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
    allowed_fields = {"title", "destinations", "start_date", "end_date", "notes"}
    updates = {k: v for k, v in data.items() if k in allowed_fields}

    if "destinations" in updates and not isinstance(updates["destinations"], list):
        return jsonify({"error": "destinations must be a list"}), 400

    updated = update_itinerary(itinerary_id, updates)
    if not updated:
        return jsonify({"error": "update failed"}), 500

    return jsonify(_build_itinerary_response(updated)), 200


@itineraries_bp.route("/api/itineraries/<itinerary_id>", methods=["DELETE"])
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

    return jsonify({"message": "itinerary deleted successfully"}), 200
