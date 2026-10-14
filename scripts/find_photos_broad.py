"""Broadened photo search for the destinations that still have none.

The first Openverse pass sent the whole place name as one query. Most
search backends AND the terms together, so "Monastere Notre Dame des
Benedictin du mont Febe Yaounde" asks for a picture captioned with all
of that and finds nothing whether or not a photo exists. An empty result
from a query like that says nothing about the world.

So each record is tried several ways, widest last:

  1. full name + Yaounde
  2. distinctive words only
  3. the two longest distinctive words
  4. landmark anchor, where the place sits inside a known one

Every result is printed with its licence. Nothing is auto-selected: the
earlier name-scoring pass produced eighteen matches and all eighteen
were wrong, so a human reads the output.

Read-only. Nothing is written and no image is downloaded.
"""

import argparse
import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "backend", "data", "destinations.json")

API = "https://api.openverse.org/v1/images/"
HEADERS = {
    "User-Agent": "kamer-go-image-search/1.0 (local dev)",
    "Accept": "application/json",
}

# Licences shippable given the credit line the cards already print.
# ND is excluded because the cards crop; NC is excluded because the app
# may carry advertising and the ambiguity is not worth a takedown.
USABLE = {"cc0", "pdm", "by", "by-sa"}

PAUSE = 1.2

STOPWORDS = {
    "de", "du", "des", "la", "le", "les", "l", "d", "et", "a", "au", "aux",
    "the", "of", "and", "en", "sur", "pour", "yaounde", "cameroun",
    "cameroon", "centre", "center", "sarl", "service", "services",
    "company", "shop", "store", "ltd", "sa", "inc",
}

# Where a place is known by the landmark it sits in or beside. A photo of
# the landmark is not a photo of the shop, so these searches are for
# reading, not for adopting.
ANCHORS = {
    "mont febe": "Mont Febe Yaounde",
    "febe": "Mont Febe Yaounde",
    "biyem": "Biyem-Assi Yaounde",
    "bastos": "Bastos Yaounde",
    "mvog": "Mvog-Ada Yaounde",
    "ngousso": "Ngousso Yaounde",
    "melen": "Melen Yaounde",
    "nkol": "Nkolbisson Yaounde",
    "messa": "Messa Yaounde",
    "mokolo": "Mokolo Yaounde",
    "etoudi": "Etoudi Yaounde",
    "tsinga": "Tsinga Yaounde",
    "essos": "Essos Yaounde",
    "ekounou": "Ekounou Yaounde",
    "obili": "Obili Yaounde",
    "ngoa": "Ngoa-Ekelle Yaounde",
}


def fold(text):
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return text.lower()


def words(name):
    return re.findall(r"[a-z0-9]+", fold(name))


def distinctive(name):
    return [w for w in words(name) if len(w) > 3 and w not in STOPWORDS]


def queries(record):
    """The query shapes to try, narrowest first."""
    name = record["name"]
    picked = distinctive(name)
    shapes = []

    shapes.append(("full name", f"{name} Yaounde"))

    if picked:
        shapes.append(("distinctive", " ".join(picked) + " Yaounde"))

    if len(picked) > 2:
        longest = sorted(picked, key=len, reverse=True)[:2]
        shapes.append(("two words", " ".join(longest) + " Yaounde"))

    folded = fold(name)
    for key, anchor in ANCHORS.items():
        if key in folded:
            shapes.append(("anchor", anchor))
            break

    # Drop duplicates while keeping order.
    seen = set()
    unique = []
    for label, query in shapes:
        if query.lower() in seen:
            continue
        seen.add(query.lower())
        unique.append((label, query))
    return unique


def search(query, page_size=6):
    params = urllib.parse.urlencode({
        "q": query, "page_size": page_size, "mature": "false",
    })
    url = f"{API}?{params}"

    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                # A throttle is not an empty result. Recording it as one
                # would turn "unknown" into "does not exist".
                wait = 20 * (attempt + 1)
                print(f"      throttled, waiting {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            if exc.code == 400:
                return {"results": []}
            time.sleep(6)
        except Exception as exc:  # noqa: BLE001
            print(f"      attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(6)

    return None  # unknown, explicitly not empty


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--usable-only", action="store_true",
                        help="hide results whose licence cannot be shipped")
    args = parser.parse_args()

    with open(DATA, encoding="utf-8") as handle:
        records = json.load(handle)

    targets = [r for r in records
               if not (r.get("image_asset") or r.get("image_url"))]
    if args.limit:
        targets = targets[:args.limit]

    print(f"destinations with no photograph: {len(targets)}")
    print("=" * 70)

    any_usable = 0
    unknown = 0

    for record in targets:
        print(f"\n{record['id']}  {record['name']}")
        shown = set()
        found_here = False

        for label, query in queries(record):
            payload = search(query)
            if payload is None:
                unknown += 1
                print(f"  [{label}] {query!r} -> SEARCH FAILED (unknown)")
                continue

            results = payload.get("results") or []
            if not results:
                print(f"  [{label}] {query!r} -> nothing")
                time.sleep(PAUSE)
                continue

            print(f"  [{label}] {query!r} -> {len(results)}")
            for result in results:
                licence = (result.get("license") or "").lower()
                usable = licence in USABLE
                if args.usable_only and not usable:
                    continue

                ident = result.get("id")
                if ident in shown:
                    continue
                shown.add(ident)

                mark = "USABLE" if usable else "no"
                title = (result.get("title") or "")[:60]
                print(f"      [{mark:<6}] {licence or '?':<7} {title!r}")
                print(f"          {result.get('creator') or '(none)'} "
                      f"via {result.get('source')}")
                print(f"          {result.get('foreign_landing_url')}")
                if usable:
                    found_here = True

            time.sleep(PAUSE)

        if found_here:
            any_usable += 1

    print(f"\n{'=' * 70}")
    print(f"searched                       : {len(targets)}")
    print(f"with at least one usable result: {any_usable}")
    print(f"searches that failed outright  : {unknown} (unknown, not absent)")
    print("\nA result is a candidate, not a match. Confirm the picture is of")
    print("that place before adopting it.")


if __name__ == "__main__":
    main()
