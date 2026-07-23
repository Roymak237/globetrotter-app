"""
app/destinations.py

Destination search endpoint.

Routes
------
GET /api/destinations
    Returns destinations that match any of the provided query parameters.
    All parameters are optional; omitting them returns the full catalogue.
"""
from flask import Blueprint, request, jsonify

from app.models import get_all_destinations, get_destination_by_id

destinations_bp = Blueprint("destinations", __name__)


@destinations_bp.route("/api/destinations", methods=["GET"])
def search_destinations():
    """Search destinations by name keyword, tag, region, and/or max_cost.

    Query parameters (all optional):
        q         – free-text search against name, region, and description
        tag       – filter by a single interest tag (e.g. "beach")
        region    – filter by region name (e.g. "South")
        max_cost  – filter by maximum average daily cost (integer)

    Returns a JSON list of matching destination objects.
    """
    q = request.args.get("q", "").strip().lower()
    tag = request.args.get("tag", "").strip().lower()
    region = request.args.get("region", "").strip().lower()
    max_cost_str = request.args.get("max_cost", "").strip()

    max_cost = None
    if max_cost_str:
        try:
            max_cost = int(max_cost_str)
        except ValueError:
            return jsonify({"error": "max_cost must be an integer"}), 400

    destinations = get_all_destinations()
    results = []

    for dest in destinations:
        # Free-text filter
        if q:
            searchable = " ".join([
                dest.get("name", ""),
                dest.get("region", ""),
                dest.get("description", ""),
            ]).lower()
            if q not in searchable:
                continue

        # Tag filter
        if tag and tag not in [t.lower() for t in dest.get("tags", [])]:
            continue

        # Region filter
        if region and region != dest.get("region", "").lower():
            continue

        # Cost filter
        if max_cost is not None:
            cost = dest.get("avg_cost_per_day")
            if cost is None or cost > max_cost:
                continue

        results.append(dest)

    return jsonify(results), 200


@destinations_bp.route("/api/destinations/<dest_id>", methods=["GET"])
def get_destination(dest_id):
    """Return a single destination by ID."""
    dest = get_destination_by_id(dest_id)
    if not dest:
        return jsonify({"error": "destination not found"}), 404
    return jsonify(dest), 200
