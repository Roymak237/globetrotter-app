"""
app/places.py

Everything answering "what is around this place, and what do people make of
it": nearby destinations, nearby amenities, and star ratings.

Amenity data comes from OpenStreetMap via the Overpass API. That choice is
deliberate — it needs no API key and no billing account, so anyone who clones
this repository gets a working deployment. The tradeoff is that Overpass is a
shared free service that can be slow or briefly unavailable, so every lookup is
cached on disk and a failed request degrades to an empty list rather than an
error page.

Routes
------
GET    /api/destinations/<dest_id>/nearby     Other destinations within range
GET    /api/destinations/<dest_id>/amenities  Restaurants, hotels, banks nearby
GET    /api/destinations/<dest_id>/rating     Aggregate plus the viewer's own
PUT    /api/destinations/<dest_id>/rating     Set the viewer's rating
DELETE /api/destinations/<dest_id>/rating     Withdraw the viewer's rating
"""
import datetime
import json
import math
import os
import threading
import urllib.error
import urllib.parse
import urllib.request

from flask import Blueprint, jsonify, request

from app.auth import get_current_user
from app.models import (
    DATA_DIR,
    delete_rating,
    get_all_destinations,
    get_destination_by_id,
    get_rating,
    rating_summary,
    save_or_update_rating,
)

places_bp = Blueprint("places", __name__)

EARTH_RADIUS_KM = 6371.0
DEFAULT_NEARBY_KM = 5.0
MAX_NEARBY_RESULTS = 12

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_TIMEOUT_SECONDS = 12
AMENITY_CACHE_FILE = os.path.join(DATA_DIR, "amenity_cache.json")
# OSM data for a fixed point changes on the order of months, so a week-long
# cache costs nothing in freshness and spares the shared Overpass service.
AMENITY_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60
AMENITY_RADIUS_METRES = 1500
MAX_AMENITY_RESULTS = 30

_CACHE_LOCK = threading.Lock()

# Categories exposed to the app, mapped onto the OSM tags that populate them.
AMENITY_CATEGORIES = {
    "food": {
        "label": "Eat & stay nearby",
        "filters": [
            'node["amenity"~"^(restaurant|cafe|fast_food|bar)$"]',
            'node["tourism"~"^(hotel|guest_house|hostel)$"]',
        ],
    },
    "money": {
        "label": "Banks & ATMs",
        "filters": ['node["amenity"~"^(bank|atm|bureau_de_change)$"]'],
    },
    "fuel": {
        "label": "Fuel stations",
        "filters": ['node["amenity"="fuel"]'],
    },
    "health": {
        "label": "Pharmacies & clinics",
        "filters": ['node["amenity"~"^(pharmacy|hospital|clinic|doctors)$"]'],
    },
    "safety": {
        "label": "Police stations",
        "filters": ['node["amenity"="police"]'],
    },
}


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in kilometres."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def _coords(destination: dict):
    """Return (lat, lon) when a destination is pinned, otherwise None."""
    lat = destination.get("latitude")
    lon = destination.get("longitude")
    if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
        return float(lat), float(lon)
    return None


def budget_band(destination: dict) -> dict:
    """Bucket a destination's daily cost into a label the UI can show.

    Cost is absent for most of the catalogue, so an explicit "unknown" is
    returned rather than defaulting to free, which would read as a claim.
    """
    cost = destination.get("avg_cost_per_day")
    if not isinstance(cost, (int, float)):
        return {"band": "unknown", "label": "Cost varies", "amount": None}
    if cost < 1000:
        return {"band": "low", "label": "Under 1,000 FCFA", "amount": cost}
    if cost <= 5000:
        return {"band": "mid", "label": "1,000 - 5,000 FCFA", "amount": cost}
    return {"band": "high", "label": "Over 5,000 FCFA", "amount": cost}


def _read_cache() -> dict:
    if not os.path.exists(AMENITY_CACHE_FILE):
        return {}
    try:
        with open(AMENITY_CACHE_FILE, "r", encoding="utf-8-sig") as fh:
            content = fh.read().strip()
            return json.loads(content) if content else {}
    except (OSError, ValueError):
        # A corrupt cache must never break the endpoint; treat it as empty.
        return {}


def _write_cache(cache: dict) -> None:
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        tmp = AMENITY_CACHE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(cache, fh)
        os.replace(tmp, AMENITY_CACHE_FILE)
    except OSError:
        # Caching is an optimisation; failing to persist it is not fatal.
        pass


def _cached_amenities(key: str):
    with _CACHE_LOCK:
        entry = _read_cache().get(key)
    if not entry:
        return None
    fetched = entry.get("fetched_at", 0)
    if (datetime.datetime.now().timestamp() - fetched) > AMENITY_CACHE_TTL_SECONDS:
        return None
    return entry.get("items", [])


def _store_amenities(key: str, items: list) -> None:
    with _CACHE_LOCK:
        cache = _read_cache()
        cache[key] = {
            "fetched_at": datetime.datetime.now().timestamp(),
            "items": items,
        }
        # Bound the cache so a large catalogue cannot grow it without limit.
        if len(cache) > 400:
            ordered = sorted(cache.items(), key=lambda kv: kv[1].get("fetched_at", 0))
            cache = dict(ordered[-400:])
        _write_cache(cache)


def _build_overpass_query(lat: float, lon: float, category: str) -> str:
    filters = AMENITY_CATEGORIES[category]["filters"]
    clauses = "".join(
        flt + "(around:" + str(AMENITY_RADIUS_METRES) + "," + str(lat) + "," + str(lon) + ");"
        for flt in filters
    )
    return (
        "[out:json][timeout:" + str(OVERPASS_TIMEOUT_SECONDS) + "];"
        "(" + clauses + ");out body 60;"
    )


def _fetch_amenities(lat: float, lon: float, category: str) -> list:
    """Query Overpass, returning [] on any failure.

    Callers treat an empty list as "nothing found", which is also the right
    thing to show when the upstream service is unreachable.
    """
    query = _build_overpass_query(lat, lon, category)
    data = urllib.parse.urlencode({"data": query}).encode("utf-8")
    req = urllib.request.Request(
        OVERPASS_URL,
        data=data,
        headers={
            # Overpass asks for a descriptive agent so operators can identify
            # unusual traffic and make contact rather than silently blocking.
            "User-Agent": "KamerGo/1.0 (+https://kamer-go.duckdns.org)",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=OVERPASS_TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        return []

    items = []
    for element in payload.get("elements", []):
        tags = element.get("tags", {}) or {}
        name = tags.get("name")
        # An unnamed node cannot be presented usefully in a list.
        if not name:
            continue
        e_lat = element.get("lat")
        e_lon = element.get("lon")
        if not isinstance(e_lat, (int, float)) or not isinstance(e_lon, (int, float)):
            continue
        items.append({
            "name": name,
            "kind": tags.get("amenity") or tags.get("tourism") or "place",
            "latitude": e_lat,
            "longitude": e_lon,
            "distance_km": round(_haversine_km(lat, lon, e_lat, e_lon), 2),
            "opening_hours": tags.get("opening_hours", ""),
            "phone": tags.get("phone") or tags.get("contact:phone") or "",
            "website": tags.get("website") or tags.get("contact:website") or "",
        })

    items.sort(key=lambda item: item["distance_km"])
    return items[:MAX_AMENITY_RESULTS]


@places_bp.route("/api/destinations/<dest_id>/nearby", methods=["GET"])
def nearby_destinations(dest_id):
    """Other catalogue destinations within range, closest first."""
    destination = get_destination_by_id(dest_id)
    if destination is None:
        return jsonify({"error": "destination not found"}), 404

    origin = _coords(destination)
    if origin is None:
        # Not an error: some catalogue entries are whole cities with no pin.
        return jsonify([]), 200

    try:
        radius = float(request.args.get("radius_km", DEFAULT_NEARBY_KM))
    except (TypeError, ValueError):
        radius = DEFAULT_NEARBY_KM
    radius = max(0.5, min(radius, 50.0))

    results = []
    for candidate in get_all_destinations():
        if candidate.get("id") == dest_id:
            continue
        point = _coords(candidate)
        if point is None:
            continue
        distance = _haversine_km(origin[0], origin[1], point[0], point[1])
        if distance > radius:
            continue
        results.append({
            "id": candidate.get("id"),
            "name": candidate.get("name"),
            "region": candidate.get("region", ""),
            "tags": candidate.get("tags", []) or [],
            "image_url": candidate.get("image_url", ""),
            "image_asset": candidate.get("image_asset", ""),
            "latitude": point[0],
            "longitude": point[1],
            "distance_km": round(distance, 2),
            "rating": rating_summary(candidate.get("id", "")),
        })

    results.sort(key=lambda item: item["distance_km"])
    return jsonify(results[:MAX_NEARBY_RESULTS]), 200


@places_bp.route("/api/destinations/<dest_id>/amenities", methods=["GET"])
def destination_amenities(dest_id):
    """Real restaurants, hotels, banks and services around a destination."""
    destination = get_destination_by_id(dest_id)
    if destination is None:
        return jsonify({"error": "destination not found"}), 404

    origin = _coords(destination)
    if origin is None:
        return jsonify({"categories": [], "located": False}), 200

    requested = str(request.args.get("category", "") or "").strip().lower()
    categories = (
        [requested] if requested in AMENITY_CATEGORIES else list(AMENITY_CATEGORIES)
    )

    payload = []
    for category in categories:
        key = dest_id + ":" + category
        items = _cached_amenities(key)
        if items is None:
            items = _fetch_amenities(origin[0], origin[1], category)
            _store_amenities(key, items)
        payload.append({
            "category": category,
            "label": AMENITY_CATEGORIES[category]["label"],
            "items": items,
        })

    return jsonify({"categories": payload, "located": True}), 200


@places_bp.route("/api/destinations/<dest_id>/rating", methods=["GET"])
def get_destination_rating(dest_id):
    """Aggregate rating, plus the viewer's own if they are signed in."""
    if get_destination_by_id(dest_id) is None:
        return jsonify({"error": "destination not found"}), 404

    username = get_current_user(request)
    mine = get_rating(dest_id, username) if username else None
    summary = rating_summary(dest_id)
    return jsonify({
        "destination_id": dest_id,
        "average": summary["average"],
        "count": summary["count"],
        "mine": mine.get("stars") if mine else None,
    }), 200


@places_bp.route("/api/destinations/<dest_id>/rating", methods=["PUT"])
def set_destination_rating(dest_id):
    """Record the viewer's star rating for a destination."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401
    if get_destination_by_id(dest_id) is None:
        return jsonify({"error": "destination not found"}), 404

    data = request.get_json(silent=True) or {}
    try:
        stars = int(data.get("stars"))
    except (TypeError, ValueError):
        return jsonify({"error": "stars must be a whole number from 1 to 5"}), 400
    if stars < 1 or stars > 5:
        return jsonify({"error": "stars must be between 1 and 5"}), 400

    save_or_update_rating({
        "destination_id": dest_id,
        "username": username,
        "stars": stars,
        "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    })

    summary = rating_summary(dest_id)
    return jsonify({
        "destination_id": dest_id,
        "average": summary["average"],
        "count": summary["count"],
        "mine": stars,
    }), 200


@places_bp.route("/api/destinations/<dest_id>/rating", methods=["DELETE"])
def clear_destination_rating(dest_id):
    """Withdraw the viewer's rating."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    if not delete_rating(dest_id, username):
        return jsonify({"error": "you have not rated this destination"}), 404

    summary = rating_summary(dest_id)
    return jsonify({
        "destination_id": dest_id,
        "average": summary["average"],
        "count": summary["count"],
        "mine": None,
    }), 200
