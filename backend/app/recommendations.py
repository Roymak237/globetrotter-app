"""
app/recommendations.py

Personalised destination recommendations.

Routes
------
GET /api/recommendations
    Returns destinations that best match the authenticated user's preferences.
    Requires a valid JWT in the Authorization header.
"""
from flask import Blueprint, request, jsonify

from app.auth import get_current_user
from app.models import get_all_destinations, get_user_by_username

recommendations_bp = Blueprint("recommendations", __name__)


@recommendations_bp.route("/api/recommendations", methods=["GET"])
def get_recommendations():
    """Return personalised destination recommendations for the logged-in user.

    Recommendations are derived by scoring each destination against the
    user's preference tags.  Destinations are returned in descending score
    order.  An optional *limit* query parameter caps the number of results
    (default 5).

    Requires: Authorization: ******
    """
    username = get_current_user(request)
    if not username:
        return jsonify({"error": "authentication required"}), 401

    user = get_user_by_username(username)
    if not user:
        return jsonify({"error": "user not found"}), 404

    preference_aliases = {
        "beach": "relaxation",
        "beaches": "relaxation",
        "relax": "relaxation",
        "outdoors": "nature",
        "wild": "wildlife",
        "families": "family",
        "markets": "market",
        "night life": "nightlife",
    }
    preferences = [
        preference_aliases.get(p.strip().lower(), p.strip().lower())
        for p in user.get("preferences", [])
        if isinstance(p, str) and p.strip()
    ]

    if not preferences:
        return jsonify([]), 200

    try:
        limit = int(request.args.get("limit", 5))
    except ValueError:
        return jsonify({"error": "limit must be an integer"}), 400

    destinations = get_all_destinations()

    scored = []
    for dest in destinations:
        dest_tags = [t.lower() for t in dest.get("tags", [])]
        score = sum(1 for pref in preferences if pref in dest_tags)
        scored.append((score, dest))

    scored.sort(key=lambda x: (-x[0], x[1].get("name", "")))

    results = []
    for score, dest in scored[:limit]:
        entry = dict(dest)
        entry["match_score"] = score
        results.append(entry)

    return jsonify(results), 200
