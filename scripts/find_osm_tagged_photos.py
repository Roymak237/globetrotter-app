"""Ask OpenStreetMap whether the places themselves name a photograph.

The earlier search guessed from names and coordinates and was wrong
almost every time: a church matched a power station, a dessert shop
matched a stadium. This asks a different question. Fifty of these
records cite an exact OSM element, and OSM elements can carry tags that
*identify* a picture rather than suggest one:

    image=<url>                 a photo of this feature
    wikimedia_commons=File:...  a Commons file of this feature
    wikipedia=<lang>:<title>    an article about this feature
    wikidata=Q...               an entity, which may carry P18

A hit from any of these is a statement by a mapper that the picture is
of that place, which is the thing proximity could never establish.

Read-only. Nothing is written and nothing is downloaded.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "backend", "data", "destinations.json")

# The core OSM API rather than Overpass. Overpass is a query engine built
# for searching, and it times out under load; this endpoint just hands
# back elements by id, which is all that is needed here.
OSM_API = "https://api.openstreetmap.org/api/0.6"
PLURAL = {"node": "nodes", "way": "ways", "relation": "relations"}

HEADERS = {"User-Agent": "kamer-go-image-search/1.0 (local dev)"}

ELEMENT_RE = re.compile(
    r"openstreetmap\.org/(node|way|relation)/(\d+)", re.I
)

# Tags that point at a picture, or at something that may hold one.
PICTURE_TAGS = (
    "image",
    "image:0",
    "wikimedia_commons",
    "wikipedia",
    "wikidata",
    "brand:wikidata",
    "operator:wikidata",
    "subject:wikidata",
    "mapillary",
    "panoramax",
)


def load():
    with open(DATA, encoding="utf-8") as handle:
        return json.load(handle)


def osm_refs(record):
    """Every OSM element this record cites, as (type, id) pairs."""
    refs = []
    for source in record.get("location_sources") or []:
        match = ELEMENT_RE.search(source)
        if match:
            refs.append((match.group(1).lower(), match.group(2)))
    return refs


def fetch(kind, idents):
    """Fetch tags for same-typed elements, by id."""
    url = (f"{OSM_API}/{PLURAL[kind]}.json?"
           + urllib.parse.urlencode({PLURAL[kind]: ",".join(idents)}))

    last_error = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=90) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                # Genuinely gone: an element deleted since the data was
                # written. Worth saying, not worth retrying.
                print(f"    {kind}s {idents}: 404, elements no longer exist",
                      file=sys.stderr)
                return {"elements": []}
            last_error = exc
            print(f"    {kind}s attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(6)
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            # A throttle or a timeout looks exactly like "no such element".
            # Retrying matters, because treating one as an absence would
            # quietly turn a maybe into a no.
            print(f"    {kind}s attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(6)

    raise RuntimeError(f"OSM API failed for {kind}s {idents}: {last_error}")


def main():
    records = load()
    photoless = [r for r in records
                 if not (r.get("image_asset") or r.get("image_url"))]

    wanted = {}
    for record in photoless:
        for ref in osm_refs(record):
            wanted[ref] = record

    print(f"{len(photoless)} destinations have no photograph")
    print(f"{len(wanted)} of them cite an exact OSM element\n")

    if not wanted:
        return

    by_type = {"node": [], "way": [], "relation": []}
    for kind, ident in sorted(wanted):
        by_type[kind].append(ident)

    found = []
    checked = 0
    for kind, idents in by_type.items():
        # Batched, because one request for twenty-five elements is kinder
        # than twenty-five requests.
        for start in range(0, len(idents), 25):
            batch = idents[start:start + 25]
            print(f"asking about {len(batch)} {kind}(s)...")
            payload = fetch(kind, batch)

            for element in payload.get("elements", []):
                checked += 1
                key = (element["type"], str(element["id"]))
                record = wanted.get(key)
                if record is None:
                    continue
                tags = element.get("tags", {})
                hits = {k: v for k, v in tags.items() if k in PICTURE_TAGS}
                if hits:
                    found.append((record, key, hits, tags.get("name")))
            time.sleep(2)

    print(f"\n{'=' * 68}")
    print(f"{checked} element(s) read back from OSM")
    if not found:
        print("No photoless destination's OSM element names a picture.")
        print("That is an answer, not a failure to search: these are shops,")
        print("cyber cafes and small churches, and nobody has tagged a")
        print("photograph onto them.")
        return

    print(f"{len(found)} element(s) carry a picture-bearing tag:\n")
    for record, key, hits, name in found:
        print(f"  {record['id']}  {record['name']}")
        print(f"      osm {key[0]}/{key[1]}  name={name!r}")
        for tag, value in sorted(hits.items()):
            print(f"      {tag} = {value}")
        print()


if __name__ == "__main__":
    main()
