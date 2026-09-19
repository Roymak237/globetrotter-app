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
from app.itineraries import _locked
from app.models import (
    get_itineraries_for_user,
    save_itinerary,
    get_itinerary_by_id,
    get_user_by_username,
    get_all_shares,
    save_share,
    get_shares_for_itinerary,
    delete_share,
)

shares_bp = Blueprint("shares", __name__)


@shares_bp.before_request
def _check_json():
    if request.method == "POST" and not isinstance(request.get_json(silent=True), dict):
        return jsonify({"error": "JSON object required"}), 400


@shares_bp.route("/api/itineraries/<itinerary_id>/share", methods=["POST"])
@_locked
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
    if not isinstance(data.get("shared_with"), str):
        return jsonify({"error": "shared_with must be a username"}), 400
    shared_with = data.get("shared_with", "").strip().lower()
    if not shared_with:
        return jsonify({"error": "shared_with username is required"}), 400

    if not get_user_by_username(shared_with):
        return jsonify({"error": "user to share with does not exist"}), 404
    if shared_with == username:
        return jsonify({"error": "choose another traveller"}), 400
    for existing in get_shares_for_itinerary(itinerary_id):
        if existing.get("shared_with") == shared_with:
            return jsonify({"message": "already shared", "share": existing}), 201

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
@_locked
def revoke_share(share_id):
    """Revoke access to a shared itinerary.

    Requires: Authorization: ******
    """
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401

    share = next((s for s in get_all_shares() if s.get("id") == share_id), None)
    if not share:
        return jsonify({"error": "share not found"}), 404

    if share.get("owner") != username:
        return jsonify({"error": "forbidden"}), 403

    deleted = delete_share(share_id)
    if not deleted:
        return jsonify({"error": "delete failed"}), 500

    return jsonify({"message": "share revoked successfully"}), 200


@shares_bp.route("/api/shares/received", methods=["GET"])
def received_shares():
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401
    results = []
    for share in get_all_shares():
        if share.get("shared_with") != username:
            continue
        itinerary = get_itinerary_by_id(share.get("itinerary_id"))
        if itinerary and itinerary.get("username") == share.get("owner"):
            results.append({**share, "itinerary": itinerary})
    return jsonify(results), 200


@shares_bp.route("/api/shares/<share_id>/claim", methods=["POST"])
@_locked
def claim_share(share_id):
    """Copy an explicitly received share. Never transfer the owner's trip."""
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401
    share = next((s for s in get_all_shares() if s.get("id") == share_id), None)
    if not share:
        return jsonify({"error": "share not found or revoked"}), 404
    if share.get("shared_with") != username:
        return jsonify({"error": "forbidden"}), 403
    original = get_itinerary_by_id(share.get("itinerary_id"))
    if not original or original.get("username") != share.get("owner"):
        return jsonify({"error": "shared itinerary unavailable"}), 404
    for existing in get_itineraries_for_user(username):
        if existing.get("source_share_id") == share_id:
            return jsonify(existing), 200
    copy = {key: original.get(key, "") for key in
            ("title", "start_date", "end_date", "notes")}
    copy.update({"id": str(uuid.uuid4()), "username": username,
                 "destinations": list(original.get("destinations", [])),
                 "visited_stops": [], "source_share_id": share_id,
                 "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat()})
    save_itinerary(copy)
    return jsonify(copy), 201
