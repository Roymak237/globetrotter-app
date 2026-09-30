"""
scripts/geocode_destinations2.py

Second pass at coordinates, with the two lessons from the first.

The first pass matched "Yaounde" to a railway station and "Parc Mvog-Betsi" to
a civil-engineering hangar. Both were returned confidently. Nominatim answers
with the best string match it can find, which is not the same as the right
place, so this pass adds two things:

1. An expected OpenStreetMap category per destination. A zoo that resolves to
   a hangar is rejected automatically rather than by someone noticing.
2. Search terms taken from the real record names, in French, which is what
   OSM carries for Yaounde.

Where no specific venue exists in OSM, the plan deliberately asks for the
neighbourhood instead, and the result is flagged approximate. A pin that
places a restaurant in Bastos is useful and true; a pin that claims to be its
doorway is not. Destinations whose record says only "Yaounde, address
unverified" are absent from the plan on purpose: there is nothing to look up,
and a guess would be worse than the blank the screen shows today.

Read-only. Writes candidates for review; does not touch destinations.json.
"""
import json
import time
import urllib.parse
import urllib.request

NOMINATIM = "https://nominatim.openstreetmap.org/search"
USER_AGENT = "kamer-go-destination-audit/1.0 (capstone project; contact via repo)"

# Categories that mean "we found an area, not the venue". Used to flag a
# result as approximate rather than to reject it.
AREA_CATEGORIES = {"place", "boundary", "landuse"}

# id -> (search terms in priority order, acceptable OSM categories)
PLAN = {
    # --- the city and its neighbourhoods -----------------------------------
    "dest-yao-001": (["Yaoundé, Cameroun"], {"place", "boundary"}),
    "dest-yao-008": (["Bastos, Yaoundé"], {"place", "boundary", "landuse"}),
    "dest-yao-010": (["Cité Verte, Yaoundé"], {"place", "boundary", "leisure"}),

    # --- markets ------------------------------------------------------------
    "dest-yao-005": (["Marché Biyem-Assi, Yaoundé", "Biyem-Assi, Yaoundé"],
                     {"amenity", "shop", "place", "boundary"}),
    "dest-yao-022": (["Marché Central, Yaoundé"], {"amenity", "shop"}),
    "dest-yao-037": (["Marché Mokolo, Yaoundé"], {"amenity", "shop"}),

    # --- landmarks ----------------------------------------------------------
    "dest-yao-006": (["Grande Mosquée de Yaoundé", "Mosquée Centrale, Yaoundé"],
                     {"amenity", "building"}),
    "dest-yao-009": (["Musée National du Cameroun, Yaoundé"],
                     {"tourism", "amenity", "building"}),
    "dest-yao-028": (["Jardin Zoologique de Mvog-Betsi, Yaoundé",
                      "Mvog-Betsi, Yaoundé"],
                     {"tourism", "leisure", "place", "boundary"}),
    "dest-yao-035": (["Biyem-Assi, Yaoundé"],
                     {"leisure", "place", "boundary"}),
    "dest-yao-038": (["Parcours Vita, Yaoundé"], {"leisure"}),

    # --- hotels and leisure -------------------------------------------------
    "dest-yao-026": (["Hôtel Mont Fébé, Yaoundé"], {"tourism", "leisure"}),
    "dest-yao-034": (["Hôtel Mont Fébé, Yaoundé"], {"tourism"}),
    "dest-yao-027": (["Biyem-Assi, Yaoundé"], {"tourism", "place", "boundary"}),

    # --- health -------------------------------------------------------------
    "dest-yao-032": (["Hôpital de District de Biyem-Assi, Yaoundé",
                      "Biyem-Assi, Yaoundé"],
                     {"amenity", "healthcare", "place", "boundary"}),

    # --- supermarkets -------------------------------------------------------
    "dest-yao-025": (["Dovv Bastos, Yaoundé"], {"shop"}),
    "dest-yao-023": (["Tongolo, Yaoundé"], {"shop", "place", "boundary"}),
    "dest-yao-024": (["Emana, Yaoundé"], {"shop", "place", "boundary"}),

    # --- businesses known only by neighbourhood -----------------------------
    # These resolve to the quarter on purpose. The record gives a district and
    # nothing more, so the district is the honest answer.
    "dest-yao-011": (["Essos, Yaoundé"], {"place", "boundary"}),
    "dest-yao-014": (["Biyem-Assi, Yaoundé"], {"place", "boundary"}),
    "dest-yao-015": (["Bastos, Yaoundé"], {"place", "boundary"}),
    "dest-yao-016": (["Bastos, Yaoundé"], {"place", "boundary"}),
    "dest-yao-017": (["Bastos, Yaoundé"], {"place", "boundary"}),
    "dest-yao-019": (["Biyem-Assi, Yaoundé"], {"place", "boundary"}),
    "dest-yao-021": (["Bastos, Yaoundé"], {"place", "boundary"}),
    "dest-yao-033": (["Bastos, Yaoundé"], {"place", "boundary"}),

    # --- schools ------------------------------------------------------------
    "dest-school-001": (["Makepe, Douala"], {"amenity", "place", "boundary"}),
    "dest-school-002": (["Université Catholique d'Afrique Centrale, Yaoundé",
                         "Nkolbisson, Yaoundé"],
                        {"amenity", "place", "boundary"}),
    "dest-school-003": (["Emana, Yaoundé"], {"amenity", "place", "boundary"}),
    "dest-school-004": (["Lycée Bilingue d'Etoug-Ebé, Yaoundé",
                         "Etoug-Ebé, Yaoundé"],
                        {"amenity", "place", "boundary"}),
    "dest-school-006": (["The ICT University, Yaoundé", "Messassi, Yaoundé"],
                        {"amenity", "place", "boundary"}),
    "dest-school-007": (["IUSTY, Yaoundé"], {"amenity"}),
    "dest-school-009": (["Lycée de Nkolbisson, Yaoundé"], {"amenity"}),
    "dest-school-011": (["Lycée Technique de Foumban", "Foumban, Cameroun"],
                        {"amenity", "place", "boundary"}),
    "dest-school-012": (["Université de Yaoundé I"], {"amenity"}),
    "dest-school-013": (["Université de Yaoundé II, Soa", "Soa, Cameroun"],
                        {"amenity", "place", "boundary"}),
}

# Deliberately absent, with the reason, so the omission reads as a decision
# rather than an oversight.
NOT_LOOKED_UP = {
    "dest-yao-012": "record gives no district, only 'Yaounde'",
    "dest-yao-013": "record gives no district, only 'Yaounde'",
    "dest-yao-018": "record gives no district, only 'Yaounde'",
    "dest-yao-020": "record names a country, not a place in the city",
    "dest-yao-030": "no lake of this name is known to exist",
    "dest-yao-036": "monument identity itself is unconfirmed",
    "dest-school-005": "campus address unverified",
    "dest-school-008": "school identity itself is unconfirmed",
}


def query(term):
    params = {
        "q": term,
        "format": "jsonv2",
        "limit": "10",
        "addressdetails": "1",
        "countrycodes": "cm",
    }
    url = f"{NOMINATIM}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        print(f"    ! {exc}")
        return []


def main():
    destinations = {
        d["id"]: d
        for d in json.load(open("backend/data/destinations.json", encoding="utf-8"))
    }

    accepted = {}
    missed = []

    for dest_id, (terms, allowed) in PLAN.items():
        dest = destinations.get(dest_id)
        if dest is None:
            print(f"{dest_id}  ?? not in destinations.json")
            continue
        print(f"{dest_id}  {dest['name']}")

        hit = None
        for term in terms:
            for result in query(term):
                if result.get("category") in allowed:
                    hit = (term, result)
                    break
            time.sleep(1.1)
            if hit:
                break

        if hit is None:
            print("    -> nothing of the right kind\n")
            missed.append(dest_id)
            continue

        term, result = hit
        approximate = result.get("category") in AREA_CATEGORIES
        print(
            f"    -> {result.get('display_name', '')[:86]}\n"
            f"       {result['lat']}, {result['lon']}  "
            f"{result.get('category')}/{result.get('type')}"
            f"{'   [AREA-LEVEL]' if approximate else ''}\n"
        )
        accepted[dest_id] = {
            "name": dest["name"],
            "query": term,
            "latitude": round(float(result["lat"]), 6),
            "longitude": round(float(result["lon"]), 6),
            "display_name": result.get("display_name", ""),
            "osm_type": result.get("osm_type"),
            "osm_id": result.get("osm_id"),
            "category": result.get("category"),
            "type": result.get("type"),
            "approximate": approximate,
        }

    with open("scripts/geocode_candidates2.json", "w", encoding="utf-8") as handle:
        json.dump(accepted, handle, indent=2, ensure_ascii=False)

    exact = sum(1 for v in accepted.values() if not v["approximate"])
    print(f"\n{len(accepted)} matched: {exact} at venue level, "
          f"{len(accepted) - exact} at neighbourhood level")
    print(f"{len(missed)} found nothing acceptable: {', '.join(missed) or 'none'}")
    print(f"{len(NOT_LOOKED_UP)} not looked up by design")


if __name__ == "__main__":
    main()
