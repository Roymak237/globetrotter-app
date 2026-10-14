"""Last attempt at photographs for the parked destinations.

Earlier passes searched Wikimedia Commons by coordinate at 80 m. That
radius is right for "is this building photographed" and wrong for "has
anyone photographed anything on this street". Since the alternative now
is deleting these records outright, it is worth widening the net and
accepting a weaker result - a photo of the immediate surroundings is
still something, provided it is labelled as such and never presented as
a picture of the venue itself.

Two passes per record:

  1. Commons geosearch at 150 m, then 400 m. Each candidate is scored on
     whether its title shares a distinctive word with the place.
  2. Commons full-text search on the distinctive words alone.

A hit is only reported, never written. Every previous sweep that scored
titles by shared words produced false matches - a power station for a
church, a stadium for a dessert shop - so the output here is a shortlist
for a person to judge, not an answer.

Run:  python scripts/final_photo_sweep.py
"""

from __future__ import annotations

import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PENDING = ROOT / "backend" / "data" / "destinations_pending_photos.json"
OUT = ROOT / ".git" / "final_sweep.json"

UA = "kamer-go-destination-tool/1.0 (github.com/Roymak237/globetrotter-app)"
API = "https://commons.wikimedia.org/w/api.php"
PAUSE = 0.6
RADII = (150, 400)

# Words that identify nothing. Scoring on these matches every venue in
# Yaounde against every other one, which is how earlier sweeps produced
# a stadium for a dessert shop.
NOISE = {
    "yaounde", "yaound", "cameroun", "cameroon", "centre", "ville",
    "restaurant", "resto", "hotel", "cyber", "centre", "complexe",
    "salle", "eglise", "église", "paroisse", "institut", "ecole", "école",
    "school", "college", "university", "universite", "université",
    "market", "marche", "marché", "carrefour", "residence", "résidence",
    "le", "la", "les", "de", "du", "des", "d", "l", "the", "et", "a",
    "au", "aux", "en", "chez", "sarl", "service", "services", "of",
    "and", "club", "stade", "jardin", "village", "business", "center",
    "world", "trading", "consulting", "formation", "technique",
    "sportif", "culturel", "saint", "sainte", "notre", "dame",
}

IMAGE_SUFFIXES = (".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff")


def deaccent(text: str) -> str:
    plain = unicodedata.normalize("NFKD", text)
    return plain.encode("ascii", "ignore").decode("ascii").lower()


def distinctive(name: str) -> list[str]:
    """Words in a name that actually single it out."""
    words = re.split(r"[^a-z0-9]+", deaccent(name))
    return [w for w in words if w and w not in NOISE and len(w) > 3]


def call(params: dict) -> dict:
    params = {**params, "format": "json", "formatversion": "2"}
    url = f"{API}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def geosearch(lat: float, lon: float, radius: int) -> list[str]:
    try:
        data = call({
            "action": "query",
            "list": "geosearch",
            "gscoord": f"{lat}|{lon}",
            "gsradius": radius,
            "gslimit": 50,
            "gsnamespace": 6,
        })
    except Exception as exc:
        print(f"      geosearch {radius}m ERROR {exc}")
        return []
    return [h["title"] for h in data.get("query", {}).get("geosearch", [])]


def textsearch(term: str) -> list[str]:
    try:
        data = call({
            "action": "query",
            "list": "search",
            "srsearch": f'{term} filetype:bitmap',
            "srnamespace": 6,
            "srlimit": 20,
        })
    except Exception as exc:
        print(f"      textsearch '{term}' ERROR {exc}")
        return []
    return [h["title"] for h in data.get("query", {}).get("search", [])]


def relevant(title: str, words: list[str]) -> list[str]:
    """Which distinctive words of the place appear in this file title."""
    low = deaccent(title)
    return [w for w in words if w in low]


def main() -> int:
    only = set(sys.argv[1:])
    parked = json.loads(PENDING.read_text(encoding="utf-8"))
    results: dict[str, dict] = {}
    if OUT.exists():
        results = json.loads(OUT.read_text(encoding="utf-8"))

    for rec in parked:
        rid = rec["id"]
        if only and rid not in only:
            continue
        if rid in results:
            continue

        words = distinctive(rec["name"])
        lat, lon = rec.get("latitude"), rec.get("longitude")
        print(f"\n{rid}  {rec['name']}")
        print(f"    distinctive words: {words or '(none - name is all generic)'}")

        nearby: list[str] = []
        if lat is not None and lon is not None:
            for radius in RADII:
                found = geosearch(lat, lon, radius)
                print(f"    {radius}m -> {len(found)} file(s) on Commons")
                nearby.extend(t for t in found if t not in nearby)
                time.sleep(PAUSE)
        else:
            print("    no coordinates, skipping geosearch")

        named: list[str] = []
        for w in words[:2]:
            hits = textsearch(f"{w} Yaounde")
            print(f"    text '{w} Yaounde' -> {len(hits)} file(s)")
            named.extend(t for t in hits if t not in named)
            time.sleep(PAUSE)

        scored = []
        for title in nearby + named:
            if not title.lower().endswith(IMAGE_SUFFIXES):
                continue
            shared = relevant(title, words)
            if shared:
                scored.append({"title": title, "shared_words": shared})

        results[rid] = {
            "name": rec["name"],
            "words": words,
            "nearby_count": len(nearby),
            "candidates": scored,
        }
        if scored:
            print(f"    => {len(scored)} candidate(s) sharing a distinctive word:")
            for c in scored[:5]:
                print(f"        {c['title']}  (on {c['shared_words']})")
        else:
            print("    => nothing whose title mentions this place")

        OUT.write_text(json.dumps(results, ensure_ascii=False, indent=2),
                       encoding="utf-8")

    withc = [r for r in results.values() if r["candidates"]]
    nearby_any = [r for r in results.values() if r["nearby_count"]]
    print(f"\n{'=' * 64}")
    print(f"records swept            : {len(results)}")
    print(f"with any Commons file near : {len(nearby_any)}")
    print(f"with a title-level match : {len(withc)}")
    for r in withc:
        print(f"    {r['name']}")
        for c in r["candidates"][:3]:
            print(f"        {c['title']}")
    print(f"\nwritten to {OUT}")
    print("\nA shared word is not a photograph of the place. Judge each one.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
