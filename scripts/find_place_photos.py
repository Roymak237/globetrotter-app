"""Find Commons photographs of places we already hold a coordinate for.

Searching Commons by name alone puts the wrong building on a card. An
earlier pass asked for "University of Yaounde II" and was handed IFORD,
which is a different institution down the road. Name search ranks by text
relevance, and text relevance does not know what a building looks like.

Every record this script considers carries an exact coordinate taken from
a specific OpenStreetMap object, so there is a second, independent signal
available: where the photographer stood. This script requires *both*.

    - the file is geotagged within MAX_METRES of the place, and
    - the file's title shares a distinctive word with the place name

Proximity alone is not identity. A probe of these same coordinates
matched the restaurant FLORA RESTO to "Atelier wiki loves earth.jpg"
400 m away, and a hardware shop to a museum 97 m away. Both are photos of
something real near the venue, and neither is a photo *of* the venue.

Run without --apply to see what it would take; nothing is written.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fetch_destination_images import (  # noqa: E402
    Candidate,
    DESTINATIONS,
    USER_AGENT,
    clean_url,
    describe,
    download,
    search_titles,
    slugify,
)

API = "https://commons.wikimedia.org/w/api.php"
ASSET_ROOT = Path("frontend/assets/images")
ASSET_DIR = ASSET_ROOT / "destinations"

# Files checked by hand, by reading the Commons description rather than
# trusting a title. Automated matching cannot confirm these because the
# uploads carry no coordinates, so each entry records what was verified.
#
# Everything here was read on commons.wikimedia.org before being added. Do
# not add an entry because the name looks close: the inventory sweep that
# produced this list offered a power station for a church in Biyem-Assi
# and a stadium for a dessert shop, purely on shared words.
CONFIRMED: dict[str, tuple[str, str]] = {
    "dest-yao-066": (
        "File:Ecole des Travaux 01.jpg",
        # Description reads "Ecole Nationale des Travaux Publics vue de
        # 'Mini-Ferme'", categorised under Neighborhoods in Yaounde, taken
        # 2018-05-11 by Gtankam for the Wikimedians of Cameroon User Group.
        "description names the Ecole Nationale des Travaux Publics and the "
        "file is categorised under Yaounde",
    ),
}

# A photo taken more than this far away is a photo of the neighbourhood.
# The probe showed unrelated subjects appearing from ~90 m outward, so the
# radius sits below that and leans on the name check for the rest.
MAX_METRES = 80.0

# Words that carry no identifying force in Yaounde place names: every
# second venue is a "centre" or a "complexe", and "yaounde" is in both the
# place name and most file names, so neither can evidence a match.
STOPWORDS = {
    "yaounde", "yaound", "cameroun", "cameroon", "centre", "center",
    "complexe", "complex", "de", "du", "des", "la", "le", "les", "l",
    "et", "and", "the", "a", "an", "of", "sarl", "sa", "ltd", "service",
    "services", "international", "national", "nationale", "city", "ville",
    "saint", "st", "notre", "dame", "eglise", "glise", "church", "paroisse",
    "ecole", "cole", "school", "institut", "institute", "college",
    "universite", "university", "stade", "stadium", "club", "market",
    "marche", "march", "business", "world", "group", "groupe", "new",
}


def fold(value: str) -> str:
    """Strip accents without deleting the letters underneath them.

    Folding with NFKD keeps "reunification" and "réunification" comparable.
    An earlier version stripped non-ASCII outright, which turned the second
    into "runification" and let a duplicate monument through.
    """
    decomposed = unicodedata.normalize("NFKD", value)
    return "".join(c for c in decomposed if not unicodedata.combining(c))


def words(value: str) -> set[str]:
    """Distinctive lowercase words, with the generic ones removed."""
    tokens = re.findall(r"[a-z0-9]+", fold(value).lower())
    return {t for t in tokens if len(t) > 2 and t not in STOPWORDS}


def metres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    dy = (lat1 - lat2) * 111_320
    dx = (lon1 - lon2) * 111_320 * math.cos(math.radians(lat1))
    return math.hypot(dx, dy)


def _get(params: dict, attempts: int = 5) -> dict:
    """Call the API, backing off when Commons asks us to slow down.

    A 429 reads like a dead link if you do not handle it. An earlier audit
    reported nine broken images when eight were simply rate limits from an
    unthrottled sweep.
    """
    params = {**params, "format": "json", "formatversion": "2"}
    url = f"{API}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == attempts - 1:
                raise
            time.sleep(2 ** attempt)
        except Exception:
            if attempt == attempts - 1:
                raise
            time.sleep(2 ** attempt)
    return {}


def nearby_files(lat: float, lon: float, radius: int) -> dict[str, float]:
    """Commons files geotagged near a point, mapped to their distance."""
    try:
        data = _get({
            "action": "query", "list": "geosearch",
            "gscoord": f"{lat}|{lon}", "gsradius": str(radius),
            "gslimit": "40", "gsnamespace": "6",
        })
    except Exception as error:
        print(f"    geosearch failed: {error}", file=sys.stderr)
        return {}
    return {
        row["title"]: float(row.get("dist", radius))
        for row in data.get("query", {}).get("geosearch", [])
    }


def evidence(record: dict) -> tuple[Candidate, str] | None:
    """Return a photo we can defend as being of this place, or nothing.

    The returned string is the reason, so a human reviewing the run can
    check the claim rather than trust the score.
    """
    lat = record.get("latitude")
    lon = record.get("longitude")
    if lat is None or lon is None:
        return None

    place_words = words(record["name"])
    if not place_words:
        # Nothing distinctive left to match on - "Le Premium" reduces to
        # "premium", "reposoire" to "reposoire". Without a second signal a
        # proximity hit is a guess, so decline rather than gamble.
        return None

    near = nearby_files(lat, lon, int(MAX_METRES))
    time.sleep(1.0)
    if not near:
        return None

    overlapping = {
        title: dist for title, dist in near.items()
        if words(title) & place_words
    }
    if not overlapping:
        return None

    candidates = describe(sorted(overlapping, key=overlapping.get)[:10])
    time.sleep(1.0)
    if not candidates:
        return None

    candidates.sort(key=lambda c: (c.width >= c.height, c.width), reverse=True)
    best = candidates[0]
    shared = sorted(words(best.title) & place_words)
    reason = (f"{round(overlapping[best.title])} m away, "
              f"name shares {', '.join(shared)}")
    return best, reason


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="download matches and update the data file")
    args = parser.parse_args()

    raw = json.loads(DESTINATIONS.read_text(encoding="utf-8"))
    records = raw if isinstance(raw, list) else raw.get("destinations", raw)

    targets = [r for r in records
               if not (r.get("image_asset") or "").strip()
               and not (r.get("image_url") or "").strip()
               and r.get("latitude") is not None]

    print(f"{len(targets)} places have no photo and a coordinate to search "
          f"from\n")

    matched: list[tuple[dict, Candidate, str]] = []
    by_id = {r["id"]: r for r in records}

    for place_id, (title, why) in CONFIRMED.items():
        record = by_id.get(place_id)
        if record is None or record not in targets:
            continue
        found = describe([title])
        time.sleep(1.0)
        if not found:
            print(f"  {place_id}: {title} is gone or no longer reusable",
                  file=sys.stderr)
            continue
        matched.append((record, found[0], f"confirmed by hand - {why}"))

    for record in targets:
        if record["id"] in CONFIRMED:
            continue
        found = evidence(record)
        if not found:
            continue
        candidate, reason = found
        matched.append((record, candidate, reason))

    for record, candidate, reason in matched:
        print(f"  {record['id']}  {record['name'][:42]}")
        print(f"      {candidate.title[5:][:64]}")
        print(f"      {reason}; {candidate.licence}")

    print(f"\n{len(matched)} of {len(targets)} have a photo we can stand "
          f"behind")

    if not args.apply:
        print("\nnothing written (pass --apply to download)")
        return 0

    for record, candidate, _ in matched:
        asset = f"destinations/{slugify(record['name'])}{candidate.extension}"
        written = download(candidate, ASSET_ROOT / asset)
        record["image_asset"] = asset
        record["image_url"] = clean_url(candidate.url)
        record["image_attribution"] = candidate.attribution()
        print(f"  wrote {asset} ({written // 1024} KB)")
        time.sleep(1.0)

    DESTINATIONS.write_text(
        json.dumps(raw, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"\nupdated {DESTINATIONS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
