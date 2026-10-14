"""Locate the new photo subjects against OpenStreetMap.

The images dropped into assets/images are mostly of places that are not
in destinations.json at all - hotels, bars, churches, restaurants. To
add them we need coordinates and an address, and those have to be
looked up rather than invented.

Nominatim is queried with a few phrasings per place, because "Hilton"
alone is ambiguous worldwide while "Hilton Yaounde" is not. Results are
restricted to Cameroon and the best is kept with its OSM id so the pin
can be audited later.

Nothing is written into destinations.json here. The output is JSON for
a human to read, and places that are not found stay not found - the
schema already supports a record with no pin, and that is the honest
representation.

Run:  python scripts/geocode_new_photos.py
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
IMAGES = ROOT / "frontend" / "assets" / "images"
OUT = ROOT / ".git" / "geocode_new.json"

# Nominatim asks for a real identifier and at most one call a second.
UA = "kamer-go-destination-tool/1.0 (github.com/Roymak237/globetrotter-app)"
PAUSE = 1.2
ENDPOINT = "https://nominatim.openstreetmap.org/search"

# Filenames as dropped, mapped to the search phrasings worth trying.
# Written out rather than derived because "my-second-visit-to-mahima"
# is a blog post title, not a place name, and no amount of string
# munging turns it into one.
SUBJECTS: dict[str, list[str]] = {
    "Black&White sportsbar": ["Black and White Sports Bar Yaounde"],
    "Bois d'ebene": ["Bois d'Ebene Yaounde", "Bois d'Ebene restaurant Yaounde"],
    "cathedrale-nd-des-victoires": [
        "Cathedrale Notre-Dame des Victoires Yaounde",
        "Cathedrale Notre Dame des Victoires",
    ],
    "charles-atangana": [
        "Monument Charles Atangana Yaounde",
        "Charles Atangana Yaounde",
    ],
    "Chez kalli": ["Chez Kalli Yaounde"],
    "Chez wou": ["Chez Wou Yaounde", "Chez Wou restaurant Yaounde"],
    "Cosy pool": ["Cosy Pool Yaounde"],
    "hilton yaounde pool-exterior": ["Hilton Yaounde", "Hotel Hilton Yaounde"],
    "hotel merina yaounde facade-de-l-hotel-a-la": [
        "Hotel Merina Yaounde",
        "Merina Yaounde",
    ],
    "hotel-la-falaise": [
        "Hotel La Falaise Yaounde",
        "La Falaise Yaounde",
    ],
    "inside-salsa": ["Inside Salsa Yaounde"],
    "L'orient rouge": ["L'Orient Rouge Yaounde", "Orient Rouge Yaounde"],
    "Le Bacchus plus": ["Le Bacchus Yaounde", "Bacchus Plus Yaounde"],
    "Le Bayama Obala": ["Bayama Obala", "Le Bayama Obala Cameroon"],
    "Le Moulin de france": [
        "Le Moulin de France Yaounde",
        "Moulin de France Yaounde",
    ],
    "maison blanche": ["Maison Blanche Yaounde"],
    "musee-ethnographique": [
        "Musee Ethnographique Yaounde",
        "Musee ethnographique Cameroun",
    ],
    "my-second-visit-to-mahima": ["Mahima Yaounde", "Mahima supermarket Yaounde"],
    "o-paletuvier": ["O Paletuvier Yaounde", "Le Paletuvier Yaounde"],
    "Ole! Vins et Tapas": ["Ole Vins et Tapas Yaounde", "Ole Tapas Yaounde"],
    "paroisse saint-esprit de Mvoyle-3": [
        "Paroisse Saint-Esprit Mvolye Yaounde",
        "Eglise Saint Esprit Mvolye",
        "Mvolye Yaounde",
    ],
    "prodiges-hotel": ["Prodiges Hotel Yaounde", "Hotel Prodiges Yaounde"],
    "Residence la paix": ["Residence La Paix Yaounde"],
    "Residence Massou": ["Residence Massou Yaounde"],
    "Restaurant le colisse": [
        "Le Colisee Yaounde",
        "Restaurant Le Colisee Yaounde",
    ],
    "safyad-hotel": ["Safyad Hotel Yaounde", "Hotel Safyad Yaounde"],
    "seven hills yaounde": ["Seven Hills Yaounde", "Seven Hills Hotel Yaounde"],
    "starland hotel bastos": [
        "Starland Hotel Bastos Yaounde",
        "Starland Hotel Yaounde",
    ],
    "The Famous": ["The Famous Yaounde"],
}


def ask(query: str) -> list[dict]:
    params = urllib.parse.urlencode(
        {
            "q": query,
            "format": "jsonv2",
            "addressdetails": 1,
            "countrycodes": "cm",
            "limit": 5,
        }
    )
    req = urllib.request.Request(f"{ENDPOINT}?{params}", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def squash(text: str) -> str:
    plain = unicodedata.normalize("NFKD", text)
    plain = plain.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", "", plain.lower())


def main() -> int:
    only = set(sys.argv[1:])
    results: dict[str, dict] = {}
    if OUT.exists():
        results = json.loads(OUT.read_text(encoding="utf-8"))

    for stem, queries in SUBJECTS.items():
        if only and stem not in only:
            continue
        if stem in results and results[stem].get("status") == "found":
            continue

        print(f"\n{stem}")
        best = None
        for q in queries:
            try:
                hits = ask(q)
            except Exception as exc:  # network, 429, anything
                print(f"    '{q}' -> ERROR {exc}")
                time.sleep(PAUSE * 3)
                continue
            print(f"    '{q}' -> {len(hits)} hit(s)")
            for h in hits[:3]:
                print(f"        {h.get('display_name','')[:95]}")
            if hits and best is None:
                # Prefer a hit whose name actually resembles the query,
                # so "Hilton Yaounde" does not silently settle for a
                # road called Hilton.
                want = squash(q.replace(" Yaounde", "").replace(" Cameroon", ""))
                scored = [
                    h
                    for h in hits
                    if want and want[:8] in squash(h.get("name") or h.get("display_name", ""))
                ]
                best = (scored or hits)[0]
                best["_query"] = q
            time.sleep(PAUSE)

        if best is None:
            results[stem] = {"status": "not_found", "queries": queries}
            print("    => not found")
        else:
            results[stem] = {
                "status": "found",
                "query": best.get("_query"),
                "name": best.get("name"),
                "display_name": best.get("display_name"),
                "lat": float(best["lat"]),
                "lon": float(best["lon"]),
                "osm_type": best.get("osm_type"),
                "osm_id": best.get("osm_id"),
                "category": best.get("category"),
                "type": best.get("type"),
                "address": best.get("address"),
            }
            print(f"    => {best.get('display_name','')[:95]}")

        OUT.write_text(
            json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    found = sum(1 for v in results.values() if v.get("status") == "found")
    print(f"\n{'=' * 60}")
    print(f"subjects : {len(results)}")
    print(f"found    : {found}")
    print(f"not found: {len(results) - found}")
    print(f"\nwritten to {OUT}")
    print("\nA Nominatim hit is not proof. Read display_name before trusting it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
