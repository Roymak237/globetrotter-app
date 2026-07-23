"""
app/shares.py

Share itineraries with other users.

Routes
------
POST /api/itineraries/<id>/share  – share an itinerary with a user
GET  /api/itineraries/<id>/share  – list shares for an itinerary
DELETE /api/shares/<id>           – revoke a share
"""
import uuid
import datetime

from flask import Blueprint, request, jsonify

from app.auth import get_current_user
from app.models import (
    get_itinerary_by_id,
    get_user_by_username,
    save_share,
    get_shares_for_itinerary,
    delete_share,
)

shares_bp = Blueprint("shares", __name__)


@shares_bp.route("/api/itineraries/<itinerary_id>/share", methods=["POST"])
def share_itinerary(itinerary_id):
    """Share an itinerary with another user by username.

    Expected JSON body:
        { "shared_with": "friend_user" }

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
    shared_with = data.get("shared_with", "").strip()
    if not shared_with:
        return jsonify({"error": "shared_with username is required"}), 400

    if not get_user_by_username(shared_with):
        return jsonify({"error": "user to share with does not exist"}), 404

    # Create share record
    share = {
        "id": str(uuid.uuid4()),
        "itinerary_id": itinerary_id,
        "owner": username,
        "shared_with": shared_with,
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    save_share(share)
    return jsonify({"message": "itinerary shared successfully", "share": share}), 201


@shares_bp.route("/api/itineraries/<itinerary_id>/share", methods=["GET"])
def list_shares(itinerary_id):
    """List all shares for an itinerary.

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

    shares = get_shares_for_itinerary(itinerary_id)
    return jsonify(shares), 200


@shares_bp.route("/api/shares/<share_id>", methods=["DELETE"])
def revoke_share(share_id):
    """Revoke access to a shared itinerary.

    Requires: Authorization: ******
    """
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401

    share = next((s for s in __import__("app.models", fromlist=["get_all_shares"]).get_all_shares() if s.get("id") == share_id), None)
    if not share:
        return jsonify({"error": "share not found"}), 404

    if share.get("owner") != username:
        return jsonify({"error": "forbidden"}), 403

    deleted = delete_share(share_id)
    if not deleted:
        return jsonify({"error": "delete failed"}), 500

    return jsonify({"message": "share revoked successfully"}), 200
