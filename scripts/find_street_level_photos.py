"""Look for street-level photographs of the destinations that have none.

Every earlier search looked for a photograph *captioned* with the place
name. That is the wrong shape of question for a cyber cafe in Biyem-Assi:
nobody uploads a captioned portrait of one, but a car with a camera on
the roof may well have driven past it.

Street-level imagery is organised by position instead. Forty-nine of the
fifty photoless records cite an exact OSM element, so each one has a
coordinate, and a picture taken a few metres away facing the right
direction is a picture of that place.

Two open providers are tried, in order:

  Panoramax  https://api.panoramax.xyz  open, no key, CC-BY-SA
  Mapillary  https://graph.mapillary.com needs a token, CC-BY-SA

Proximity alone is not identity - that mistake has already been made in
this repository, where a restaurant matched a photo 400 metres away.
So the radius is tight, every hit is reported with its distance and a
link, and nothing is adopted automatically.

Read-only. Nothing is written and no image is downloaded.
"""

import argparse
import json
import math
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "backend", "data", "destinations.json")

HEADERS = {
    "User-Agent": "kamer-go-image-search/1.0 (local dev)",
    "Accept": "application/json",
}

# Metres. A shopfront photographed from the road is within this; beyond
# it the camera is more likely looking at something else entirely.
RADIUS = 35.0

PANORAMAX = "https://api.panoramax.xyz/api/search"
MAPILLARY = "https://graph.mapillary.com/images"

PAUSE = 1.0


def metres(lat1, lon1, lat2, lon2):
    """Great-circle distance, which at these scales is plenty accurate."""
    radius = 6371000.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = (math.sin(dp / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2)
    return 2 * radius * math.asin(math.sqrt(a))


def bbox(lat, lon, radius):
    """A degree box that contains the circle of the given radius."""
    dlat = radius / 111320.0
    dlon = radius / (111320.0 * max(0.2, math.cos(math.radians(lat))))
    return (lon - dlon, lat - dlat, lon + dlon, lat + dlat)


def get(url, label):
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                print(f"    {label}: {exc.code}, needs a token", file=sys.stderr)
                return None
            if exc.code == 429:
                wait = 15 * (attempt + 1)
                print(f"    {label}: throttled, waiting {wait}s",
                      file=sys.stderr)
                time.sleep(wait)
                continue
            if exc.code == 404:
                return {}
            print(f"    {label} attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(5)
        except Exception as exc:  # noqa: BLE001
            # A timeout is not an empty result. Recording one as the other
            # would turn "unknown" into "nothing exists".
            print(f"    {label} attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(5)
    return None


def search_panoramax(lat, lon, radius):
    west, south, east, north = bbox(lat, lon, radius)
    url = PANORAMAX + "?" + urllib.parse.urlencode({
        "bbox": f"{west},{south},{east},{north}",
        "limit": 25,
    })
    payload = get(url, "panoramax")
    if payload is None:
        return None

    hits = []
    for feature in payload.get("features", []):
        geometry = feature.get("geometry") or {}
        coords = geometry.get("coordinates") or []
        if len(coords) < 2:
            continue
        distance = metres(lat, lon, coords[1], coords[0])
        if distance > radius:
            continue
        props = feature.get("properties", {})
        hits.append({
            "distance": distance,
            "id": feature.get("id"),
            "when": props.get("datetime"),
            "licence": props.get("license") or "CC-BY-SA (Panoramax default)",
            "link": f"https://api.panoramax.xyz/#focus=pic&pic={feature.get('id')}",
        })
    hits.sort(key=lambda h: h["distance"])
    return hits


def search_mapillary(lat, lon, token, radius):
    west, south, east, north = bbox(lat, lon, radius)
    url = MAPILLARY + "?" + urllib.parse.urlencode({
        "access_token": token,
        "bbox": f"{west},{south},{east},{north}",
        "fields": "id,computed_geometry,geometry,captured_at,thumb_1024_url",
        "limit": 25,
    })
    payload = get(url, "mapillary")
    if payload is None:
        return None

    hits = []
    for item in payload.get("data", []):
        geometry = item.get("computed_geometry") or item.get("geometry") or {}
        coords = geometry.get("coordinates") or []
        if len(coords) < 2:
            continue
        distance = metres(lat, lon, coords[1], coords[0])
        if distance > radius:
            continue
        hits.append({
            "distance": distance,
            "id": item.get("id"),
            "when": item.get("captured_at"),
            "licence": "CC-BY-SA 4.0 (Mapillary)",
            "link": f"https://www.mapillary.com/app/?pKey={item.get('id')}",
            "thumb": item.get("thumb_1024_url"),
        })
    hits.sort(key=lambda h: h["distance"])
    return hits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mapillary-token", default=os.environ.get(
        "MAPILLARY_TOKEN", ""))
    parser.add_argument("--radius", type=float, default=RADIUS)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--all", action="store_true",
                        help="include destinations that already have a photo, "
                             "as a control on whether the search works")
    args = parser.parse_args()

    radius = args.radius

    with open(DATA, encoding="utf-8") as handle:
        records = json.load(handle)

    if args.all:
        targets = [r for r in records if r.get("latitude") is not None]
        heading = "CONTROL: every mapped destination"
    else:
        targets = [r for r in records
                   if not (r.get("image_asset") or r.get("image_url"))
                   and r.get("latitude") is not None]
        heading = "destinations with no photograph, that have a pin"

    if args.limit:
        targets = targets[:args.limit]

    print(f"{heading}: {len(targets)}")
    print(f"radius: {radius:.0f} m")
    if not args.mapillary_token:
        print("mapillary: no token given, skipping "
              "(set MAPILLARY_TOKEN or pass --mapillary-token)")
    print("=" * 70)

    with_coverage = 0
    unknown = 0

    for record in targets:
        lat = record["latitude"]
        lon = record["longitude"]
        print(f"\n{record['id']}  {record['name']}")
        print(f"  {lat:.6f},{lon:.6f}")

        found_any = False

        pano = search_panoramax(lat, lon, radius)
        if pano is None:
            unknown += 1
            print("  panoramax: SEARCH FAILED (unknown, not absent)")
        elif not pano:
            print("  panoramax: no coverage")
        else:
            found_any = True
            print(f"  panoramax: {len(pano)} picture(s) within {radius:.0f} m")
            for hit in pano[:5]:
                print(f"      {hit['distance']:5.1f} m  {hit['when']}  "
                      f"{hit['licence']}")
                print(f"          {hit['link']}")

        if args.mapillary_token:
            time.sleep(PAUSE)
            mapi = search_mapillary(lat, lon, args.mapillary_token, radius)
            if mapi is None:
                unknown += 1
                print("  mapillary: SEARCH FAILED (unknown, not absent)")
            elif not mapi:
                print("  mapillary: no coverage")
            else:
                found_any = True
                print(f"  mapillary: {len(mapi)} picture(s) within "
                      f"{radius:.0f} m")
                for hit in mapi[:5]:
                    print(f"      {hit['distance']:5.1f} m  {hit['licence']}")
                    print(f"          {hit['link']}")

        if found_any:
            with_coverage += 1
        time.sleep(PAUSE)

    print(f"\n{'=' * 70}")
    print(f"checked                 : {len(targets)}")
    print(f"with street-level nearby: {with_coverage}")
    print(f"searches that failed    : {unknown} (unknown, not absent)")
    print("\nA picture near a place is not a picture of it. Open each link")
    print("and confirm the camera is actually facing the venue.")


if __name__ == "__main__":
    main()
