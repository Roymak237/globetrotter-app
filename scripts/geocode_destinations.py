"""
scripts/geocode_destinations.py

Looks up real coordinates for destinations from OpenStreetMap's Nominatim.

Written because the alternative was inventing coordinates, and a travel app
that puts a pin in the wrong place is worse than one that admits it does not
know. Every result here carries the OSM object it came from, so a reviewer can
check any pin against its source rather than trusting this script.

Read-only: prints a report and writes a candidates file. It does not modify
destinations.json. Deciding which candidates are good enough is a judgement
call and stays with a human.

Nominatim's usage policy allows at most one request per second and requires a
identifying User-Agent. Both are respected below.
"""
import json
import sys
import time
import urllib.parse
import urllib.request

NOMINATIM = "https://nominatim.openstreetmap.org/search"
USER_AGENT = "kamer-go-destination-audit/1.0 (capstone project; contact via repo)"

# Yaounde and Cameroon, roughly. A result outside this box is a different
# place with a similar name, which is the most likely failure mode for names
# like "National Museum" or "Central Market".
CAMEROON_BBOX = (8.0, 1.5, 16.5, 13.5)  # west, south, east, north


def query(term, viewbox=True):
    params = {
        "q": term,
        "format": "jsonv2",
        "limit": "5",
        "addressdetails": "1",
        "countrycodes": "cm",
    }
    if viewbox:
        params["viewbox"] = ",".join(str(v) for v in CAMEROON_BBOX)
        params["bounded"] = "1"

    url = f"{NOMINATIM}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        print(f"    ! lookup failed: {exc}")
        return []


def main():
    destinations = json.load(open("backend/data/destinations.json", encoding="utf-8"))

    # Search terms per destination. The bare name is often too generic
    # ("National Museum"), so the region and city are appended.
    targets = []
    for d in destinations:
        if d.get("latitude") is not None:
            continue
        targets.append(d)

    print(f"{len(targets)} destinations without coordinates\n")

    found = {}
    for d in targets:
        name = d["name"]
        # Strip the audit suffixes a previous pass added to names.
        clean = name.split(" (")[0].strip()
        terms = [f"{clean}, Yaounde, Cameroon", f"{clean}, Cameroon"]

        print(f"{d['id']}  {name}")
        for term in terms:
            results = query(term)
            time.sleep(1.1)  # Nominatim policy: <= 1 req/sec
            if results:
                best = results[0]
                print(
                    f"    -> {best.get('display_name','')[:90]}\n"
                    f"       {best['lat']}, {best['lon']}"
                    f"   type={best.get('type')} osm={best.get('osm_type')}/{best.get('osm_id')}"
                )
                found[d["id"]] = {
                    "name": name,
                    "query": term,
                    "lat": float(best["lat"]),
                    "lon": float(best["lon"]),
                    "display_name": best.get("display_name", ""),
                    "osm": f"{best.get('osm_type')}/{best.get('osm_id')}",
                    "category": best.get("category"),
                    "type": best.get("type"),
                }
                break
        else:
            print("    -> no match")
        print()

    out = "scripts/geocode_candidates.json"
    json.dump(found, open(out, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    print(f"\n{len(found)}/{len(targets)} matched. Candidates written to {out}")
    print("Review before use: a confident match to the wrong place is the "
          "failure mode this cannot detect by itself.")


if __name__ == "__main__":
    sys.exit(main())
