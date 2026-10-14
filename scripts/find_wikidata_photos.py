"""Ask Wikidata whether these places have an image of their own.

Checked earlier: the `wikidata` tag on all 49 OSM elements the photoless
records cite. None carried one. That rules out the link from the map, but
not the entity itself - a place can have a Wikidata item without anyone
having tagged the OSM node with its id.

So this searches Wikidata by name and reads P18 (image) off whatever it
finds, plus P154 (logo) and P8517 (view).

Every candidate is printed with its description so a person can see
whether the entity is even the right kind of thing. "Beacon" matching a
lighthouse in Scotland is the failure mode here.

Read-only.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "backend", "data", "destinations.json")

API = "https://www.wikidata.org/w/api.php"
HEADERS = {
    "User-Agent": "kamer-go-image-search/1.0 (local dev)",
    "Accept": "application/json",
}

IMAGE_PROPERTIES = {
    "P18": "image",
    "P154": "logo",
    "P8517": "view",
    "P5252": "winter view",
    "P3451": "night view",
}

PAUSE = 2.5


def call(params):
    url = API + "?" + urllib.parse.urlencode({**params, "format": "json"})
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                # Wikimedia throttles hard and recovers slowly. Backing
                # off properly is the difference between "no picture
                # exists" and "we were not allowed to ask".
                wait = 20 * (attempt + 1)
                print(f"    throttled, waiting {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            print(f"    attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(8)
        except Exception as exc:  # noqa: BLE001
            print(f"    attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(8)
    return None


def search(name):
    for language in ("en", "fr"):
        payload = call({
            "action": "wbsearchentities",
            "search": name,
            "language": language,
            "uselang": language,
            "limit": 5,
            "type": "item",
        })
        if payload is None:
            return None
        results = payload.get("search") or []
        if results:
            return results
    return []


def images_on(ids):
    payload = call({
        "action": "wbgetentities",
        "ids": "|".join(ids),
        "props": "claims|labels|descriptions",
        "languages": "en|fr",
    })
    if payload is None:
        return {}

    found = {}
    for ident, entity in (payload.get("entities") or {}).items():
        claims = entity.get("claims") or {}
        pictures = []
        for prop, label in IMAGE_PROPERTIES.items():
            for claim in claims.get(prop, []):
                value = (((claim.get("mainsnak") or {}).get("datavalue")
                          or {}).get("value"))
                if isinstance(value, str):
                    pictures.append((label, value))
        if pictures:
            found[ident] = pictures
    return found


def main():
    only = set(sys.argv[1:])

    with open(DATA, encoding="utf-8") as handle:
        records = json.load(handle)

    targets = [r for r in records
               if not (r.get("image_asset") or r.get("image_url"))]
    if only:
        targets = [r for r in targets if r["id"] in only]

    print(f"destinations with no photograph: {len(targets)}")
    print("=" * 70)

    hits = 0
    failures = 0

    for record in targets:
        results = search(record["name"])
        if results is None:
            failures += 1
            print(f"\n{record['id']}  {record['name']}")
            print("  SEARCH FAILED (unknown, not absent)")
            continue

        if not results:
            time.sleep(PAUSE)
            continue

        ids = [r["id"] for r in results]
        pictures = images_on(ids)
        if not pictures:
            time.sleep(PAUSE)
            continue

        print(f"\n{record['id']}  {record['name']}")
        for result in results:
            if result["id"] not in pictures:
                continue
            hits += 1
            print(f"  {result['id']}  {result.get('label')!r}")
            print(f"      {result.get('description') or '(no description)'}")
            print(f"      https://www.wikidata.org/wiki/{result['id']}")
            for label, filename in pictures[result["id"]]:
                quoted = urllib.parse.quote(filename.replace(" ", "_"))
                print(f"      {label}: {filename}")
                print(f"          https://commons.wikimedia.org/wiki/File:{quoted}")
        time.sleep(PAUSE)

    print(f"\n{'=' * 70}")
    print(f"searched            : {len(targets)}")
    print(f"entities with a image: {hits}")
    print(f"searches that failed: {failures} (unknown, not absent)")
    print("\nA name match is not an identity. Read each description before")
    print("believing the picture is of the Yaounde place.")


if __name__ == "__main__":
    main()
