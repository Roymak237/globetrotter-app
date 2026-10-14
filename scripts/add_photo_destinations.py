"""Turn the newly supplied photographs into destination records.

Most of the images dropped into assets/images are of places that were never
in the catalogue - hotels, bars, churches, a museum. This builds a record
for each one from what is actually known:

  - coordinates and address come from the Nominatim lookup in
    geocode_new_photos.py, keyed by OSM id so a pin can be audited
  - the photograph is the file that prompted the record
  - price is left null, because none was supplied and inventing one would
    be worse than admitting we do not have it

Places the lookup could not resolve are still added. The schema already
carries records with no pin (see dest-yao-013), and a photograph with an
honest "we do not know exactly where" beats discarding the photograph.

Run:  python scripts/add_photo_destinations.py [--apply]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "backend" / "data" / "destinations.json"
PENDING = ROOT / "backend" / "data" / "destinations_pending_photos.json"
GEO = ROOT / ".git" / "geocode_new.json"
IMAGES = ROOT / "frontend" / "assets" / "images"

# What each new photograph shows, and how to file it. Written out by hand
# because only a person can say that "my-second-visit-to-mahima" is a
# supermarket and "inside-salsa" is a bar.
#
# tags must come from the vocabulary already in destinations.json.
SUBJECTS: dict[str, dict] = {
    "Black&White sportsbar": {
        "name": "Black & White Sports Bar",
        "tags": ["nightlife", "entertainment"],
        "what": "A sports bar in Yaounde.",
    },
    "Bois d'ebene": {
        "name": "Le Bois d'Ebene",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Avenue Monseigneur Vogt, in the Centre "
                "Commercial quarter.",
    },
    "cathedrale-nd-des-victoires": {
        "name": "Cathedrale Notre-Dame des Victoires",
        "tags": ["religion", "architecture", "landmark"],
        "what": "The Catholic cathedral on Avenue Monseigneur Vogt. It is "
                "an active place of worship, so dress modestly and ask "
                "before photographing inside.",
    },
    "charles-atangana": {
        "name": "Charles Atangana Memorial",
        "tags": ["history", "monument", "landmark"],
        "what": "A memorial to Charles Atangana, the Ewondo paramount "
                "chief, in the administrative quarter.",
    },
    "Chez kalli": {
        "name": "Chez Kalli",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Rue 1.905 in Bastos.",
    },
    "Chez wou": {
        "name": "Chez Wou",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Rue Joseph Mballa Eloumdem in Bastos.",
    },
    "Cosy pool": {
        "name": "Cosy Pool",
        "tags": ["leisure", "dining", "relaxation"],
        "what": "A venue on Rue 1.866 in Bastos. OpenStreetMap lists it "
                "as a restaurant rather than a swimming pool, despite the "
                "name.",
    },
    "hilton yaounde pool-exterior": {
        "name": "Hilton Yaounde",
        "tags": ["hotel", "accommodation", "pool"],
        "what": "A hotel on Boulevard du 20 Mai in the administrative "
                "quarter. The photograph shows the pool terrace.",
    },
    "hotel merina yaounde facade-de-l-hotel-a-la": {
        "name": "Hotel Merina",
        "tags": ["hotel", "accommodation"],
        "what": "A hotel on Rue Marie Gocker in the Centre Commercial "
                "quarter. The photograph shows the frontage.",
    },
    "hotel-la-falaise": {
        "name": "Hotel La Falaise",
        "tags": ["hotel", "accommodation"],
        "what": "A hotel on Rue du Marechal Foch in the Centre Commercial "
                "quarter.",
    },
    "inside-salsa": {
        "name": "Inside Salsa",
        "tags": ["nightlife", "entertainment"],
        "what": "A bar and dance venue in Yaounde.",
    },
    "L'orient rouge": {
        "name": "L'Orient Rouge",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Rue 1.800 in Bastos.",
    },
    "Le Bacchus plus": {
        "name": "Restaurant Le Bacchus",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Rue 1.048 in Elig-Essono.",
    },
    "Le Bayama Obala": {
        "name": "Le Bayama, Obala",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant at Abokono in Obala, in the Lekie division "
                "north of Yaounde. This one is out of town.",
    },
    "Le Moulin de france": {
        "name": "Le Moulin de France",
        "tags": ["dining", "restaurant", "food"],
        "what": "A bakery and restaurant on Boulevard du 20 Mai.",
    },
    "maison blanche": {
        "name": "Maison Blanche",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Rue Rodolphe Abessolo in Mvog-Ada.",
    },
    "musee-ethnographique": {
        "name": "Musee Ethnographique et d'Histoire des Peuples de la Foret",
        "tags": ["museum", "culture", "history"],
        "what": "A museum of the peoples of the Central African forest.",
    },
    "my-second-visit-to-mahima": {
        "name": "Mahima Supermarket, Essos",
        "tags": ["shopping", "supermarket", "groceries"],
        "what": "A supermarket on Rue Jean Abanda Bili in Essos.",
    },
    "o-paletuvier": {
        "name": "O Paletuvier",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Rue 1.115 in Elig-Essono.",
    },
    "Ole! Vins et Tapas": {
        "name": "Ole! Vins et Tapas",
        "tags": ["dining", "restaurant", "nightlife"],
        "what": "A wine and tapas bar in Yaounde.",
    },
    "paroisse saint-esprit de Mvoyle-3": {
        "name": "Paroisse Saint-Esprit de Mvolye",
        "tags": ["religion", "community"],
        "what": "A Catholic parish in the Mvolye quarter. It is an active "
                "place of worship, so dress modestly and ask before "
                "photographing inside.",
    },
    "prodiges-hotel": {
        "name": "Prodiges Hotel",
        "tags": ["hotel", "accommodation"],
        "what": "A hotel in Yaounde.",
    },
    "Residence la paix": {
        "name": "Residence La Paix",
        "tags": ["lodging", "accommodation"],
        "what": "Guest accommodation in Yaounde.",
    },
    "Residence Massou": {
        "name": "Residence Massou",
        "tags": ["lodging", "accommodation"],
        "what": "Guest accommodation in Yaounde.",
    },
    "Restaurant le colisse": {
        "name": "Le Colisee",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Boulevard de l'U.R.S.S. in Bastos.",
    },
    "safyad-hotel": {
        "name": "Safyad Hotel",
        "tags": ["hotel", "accommodation"],
        "what": "A hotel in Yaounde.",
    },
    "seven hills yaounde": {
        "name": "Seven Hills",
        "tags": ["dining", "restaurant"],
        "what": "A restaurant on Avenue Mvog-Fouda Ada in the Centre "
                "Commercial quarter.",
    },
    "starland hotel bastos": {
        "name": "Starland Hotel, Bastos",
        "tags": ["hotel", "accommodation"],
        "what": "A hotel in the Bastos quarter.",
    },
    "The Famous": {
        "name": "The Famous",
        "tags": ["nightlife", "entertainment"],
        "what": "A bar on Boulevard de l'U.R.S.S. in Bastos.",
    },
}

# Cost wording per kind, matching the phrasing already used for records
# whose basis is "none".
COST_NOTE = {
    "hotel": "No room rate recorded. Contact the hotel for current prices.",
    "lodging": "No room rate recorded. Contact the property for current prices.",
    "dining": "No price recorded for this kitchen yet.",
    "nightlife": "No price recorded for this venue yet.",
    "religion": "A place of worship. There is no admission charge.",
    "museum": "No admission price recorded yet.",
    "monument": "A public monument. There is no admission charge.",
    "shopping": "Spend depends entirely on what you buy.",
    "pool": "No entry price recorded yet.",
}

ATTRIBUTION = (
    "Supplied by the project maintainer. Source and licence not yet recorded."
)

# Nominatim answers a query for a building it does not hold by handing back
# the quarter that contains it. The coordinates are real but they point at a
# neighbourhood, not a front door, and recording that as "exact" would be a
# lie that no later reader could detect.
AREA_CATEGORIES = {"boundary", "place"}
AREA_TYPES = {
    "administrative",
    "suburb",
    "neighbourhood",
    "quarter",
    "city",
    "town",
    "village",
    "hamlet",
}


def is_area_level(hit: dict) -> bool:
    return (
        hit.get("category") in AREA_CATEGORIES or hit.get("type") in AREA_TYPES
    )


def cost_for(tags: list[str]) -> tuple[str, str, int | None]:
    """Return (cost_basis, cost_notes, avg_cost_per_day) for this kind.

    The catalogue distinguishes "costs nothing", which is a price of zero,
    from "we have no price", which is null. destination_cost_test.dart
    enforces the pairing, so a free place must carry an explicit 0 rather
    than a null that merely looks free.
    """
    for tag in tags:
        if tag in COST_NOTE:
            if tag in ("religion", "monument"):
                return "free", COST_NOTE[tag], 0
            return "none", COST_NOTE[tag], None
    return "none", "No price recorded for this place yet.", None


def find_image(stem: str) -> str | None:
    """The asset path for a dropped file, relative to assets/images."""
    for path in IMAGES.rglob("*"):
        if path.is_file() and path.stem == stem:
            return path.relative_to(IMAGES).as_posix()
    return None


def main() -> int:
    apply = "--apply" in sys.argv

    records = json.loads(DATA.read_text(encoding="utf-8"))
    geo = json.loads(GEO.read_text(encoding="utf-8")) if GEO.exists() else {}
    existing_names = {r["name"].casefold() for r in records}
    claimed = {r["image_asset"] for r in records if r.get("image_asset")}

    # Continue the yao series after everything already used, parked included.
    used = {r["id"] for r in records}
    if PENDING.exists():
        used |= {r["id"] for r in json.loads(PENDING.read_text(encoding="utf-8"))}
    next_n = 1 + max(
        (int(i.rsplit("-", 1)[1]) for i in used if i.startswith("dest-yao-")),
        default=0,
    )

    created: list[dict] = []
    skipped: list[str] = []

    for stem, spec in SUBJECTS.items():
        asset = find_image(stem)
        if asset is None:
            skipped.append(f"{stem}: no image file found")
            continue
        if asset in claimed:
            skipped.append(f"{stem}: {asset} already used by another record")
            continue
        if spec["name"].casefold() in existing_names:
            skipped.append(f"{stem}: '{spec['name']}' already in the catalogue")
            continue

        hit = geo.get(stem, {})
        located = hit.get("status") == "found"
        basis, notes, cost = cost_for(spec["tags"])

        if located:
            address = hit["display_name"]
            lat, lon = hit["lat"], hit["lon"]
            source = (
                f"OpenStreetMap {hit['osm_type']}/{hit['osm_id']}, "
                f"matched on the query '{hit['query']}'"
            )
            sources = [source]
            if is_area_level(hit):
                precision = "area"
                location_notes = (
                    "OpenStreetMap does not hold this building, so the pin "
                    "marks the surrounding quarter rather than the place "
                    "itself. Expect to ask locally for the last few "
                    "hundred metres."
                )
            else:
                precision = "exact"
                location_notes = (
                    "The pin comes from the OpenStreetMap entry named in "
                    "the sources below, so it can be checked against that "
                    "record."
                )
        else:
            # Honest absence rather than a guessed pin. dest-yao-013 already
            # sets this precedent.
            address = "Yaounde, Centre, Cameroon (exact street unknown)"
            lat = lon = None
            location_notes = (
                "We have a photograph of this place but have not been able "
                "to confirm its address, so there is no map pin yet. Ask "
                "locally for directions."
            )
            precision = ""
            sources = []

        record = {
            "id": f"dest-yao-{next_n:03d}",
            "name": spec["name"],
            "region": "Centre",
            "description": spec["what"],
            "tags": spec["tags"],
            "avg_cost_per_day": cost,
            "highlights": [],
            "image_url": "",
            "image_asset": asset,
            "image_attribution": ATTRIBUTION,
            "address": address,
            "location_notes": location_notes,
            "location_sources": sources,
            "additional_image_assets": [],
            "latitude": lat,
            "longitude": lon,
            "location_precision": precision,
            "cost_notes": notes,
            "cost_basis": basis,
        }
        created.append(record)
        claimed.add(asset)
        existing_names.add(spec["name"].casefold())
        next_n += 1

    located = sum(1 for r in created if r["latitude"] is not None)
    area = sum(1 for r in created if r["location_precision"] == "area")
    print(f"new records       : {len(created)}")
    print(f"   exact pin      : {located - area}")
    print(f"   area-level pin : {area}")
    print(f"   no pin         : {len(created) - located}")
    for r in created:
        pin = r["location_precision"] or "no pin"
        print(f"    {r['id']}  {r['name']}  [{pin}]  <- {r['image_asset']}")
    if skipped:
        print(f"skipped           : {len(skipped)}")
        for line in skipped:
            print(f"    {line}")

    if not apply:
        print("\nreport only. re-run with --apply to write.")
        return 0

    merged = records + created
    merged.sort(key=lambda r: r["id"])
    DATA.write_text(
        json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"\nwrote {DATA}  ({len(merged)} destinations)")
    print("\nnow run: python scripts/verify_destination_images.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
