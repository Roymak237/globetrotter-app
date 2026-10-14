"""Search Openverse for photographs of the destinations that have none.

Openverse indexes Flickr, Wikimedia, museum collections and others, so
it is a different corpus from the Commons-only search in 54d0190. The
licence is attached to every result, which is the thing that matters:
a picture that cannot be shipped is not a picture.

Two things this script deliberately does NOT do:

  * It does not score name similarity and pick a winner. The earlier
    pass did that and was wrong eighteen times out of eighteen - a
    church matched a power station on the word "biyem assi", a dessert
    shop matched a stadium. Everything is printed for a person to read.

  * It does not treat an empty result as proof of absence without
    checking the search itself works. The --control run searches for
    places that DO have photographs; if those come back empty too, the
    query is broken rather than the world.

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

# Licences that can actually be shipped in the app, given the credit line
# the UI already prints. ND forbids the cropping the cards do; NC is
# ambiguous for an app that may one day carry advertising, so both are
# listed but flagged rather than silently accepted.
USABLE = {"cc0", "pdm", "by", "by-sa"}
FLAGGED = {"by-nc", "by-nc-sa", "by-nd", "by-nc-nd"}

PAUSE = 1.5

# Words that carry no identifying force in a Yaounde place name. A match
# on any of these alone means nothing.
STOPWORDS = {
    "de", "du", "des", "la", "le", "les", "l", "d", "et", "a", "au", "aux",
    "the", "of", "and", "en", "sur", "pour", "yaounde", "yaoundé", "cameroun",
    "cameroon", "centre", "center", "sarl", "service", "services", "complexe",
    "company", "shop", "store", "food", "resto", "restaurant", "bar", "cafe",
    "cyber", "market", "business", "consulting", "trading", "koncept",
    "concept", "club", "ltd", "sa", "inc", "international", "national",
    "nouvelle", "new", "world", "star", "stars", "bites", "good", "premium",
}


def fold(text):
    """Lowercase, strip accents, keep letters and digits."""
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return text.lower()


def distinctive(name):
    """The words in a name that could actually identify a place."""
    words = re.findall(r"[a-z0-9]+", fold(name))
    return {w for w in words if len(w) > 3 and w not in STOPWORDS}


def search(query, page_size=8):
    params = urllib.parse.urlencode({
        "q": query,
        "page_size": page_size,
        # Ask for everything and judge licences here, so a usable photo
        # is never filtered out by a mislabelled filter parameter.
        "mature": "false",
    })
    url = f"{API}?{params}"

    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                # Anonymous access is rate-limited. A throttle is not an
                # empty result and must not be recorded as one.
                wait = 20 * (attempt + 1)
                print(f"    throttled, waiting {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            if exc.code == 400:
                print(f"    bad query {query!r}: {exc}", file=sys.stderr)
                return None
            print(f"    attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(8)
        except Exception as exc:  # noqa: BLE001
            print(f"    attempt {attempt + 1}: {exc}", file=sys.stderr)
            time.sleep(8)

    print(f"    GAVE UP on {query!r} - treat as UNKNOWN, not as absent",
          file=sys.stderr)
    return None


def describe(result):
    licence = (result.get("license") or "").lower()
    if licence in USABLE:
        mark = "USABLE"
    elif licence in FLAGGED:
        mark = "RESTRICTED"
    else:
        mark = "UNKNOWN-LICENCE"

    return (mark, licence, result.get("title") or "",
            result.get("creator") or "", result.get("source") or "",
            result.get("foreign_landing_url") or result.get("url") or "")


def report(record, results, name_words):
    """Print every result, marking which share a distinctive word.

    The mark is a reading aid, not a verdict. A shared word is necessary
    for a match and nowhere near sufficient, which is exactly the trap
    the earlier search fell into.
    """
    print(f"\n  {record['id']}  {record['name']}")

    if results is None:
        print("      SEARCH FAILED - unknown, not absent")
        return []

    if not results:
        print("      no results")
        return []

    candidates = []
    for result in results:
        mark, licence, title, creator, source, link = describe(result)
        overlap = name_words & distinctive(title)
        flag = f"  <- shares {sorted(overlap)}" if overlap else ""
        print(f"      [{mark:<15}] {licence or '?':<8} {title[:58]!r}{flag}")
        print(f"          {creator or '(no creator)'} via {source} - {link}")
        if overlap and mark == "USABLE":
            candidates.append((record, result, overlap))

    return candidates


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--control", action="store_true",
        help="search for destinations that already HAVE a photo, to measure "
             "whether this search can find anything at all")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    with open(DATA, encoding="utf-8") as handle:
        records = json.load(handle)

    if args.control:
        targets = [r for r in records if r.get("image_asset")]
        heading = "CONTROL: destinations that already have a photograph"
    else:
        targets = [r for r in records
                   if not (r.get("image_asset") or r.get("image_url"))]
        heading = "destinations with no photograph"

    if args.limit:
        targets = targets[:args.limit]

    print(f"{heading}: {len(targets)}")
    print("=" * 70)

    candidates = []
    failures = 0
    empty = 0

    for record in targets:
        words = distinctive(record["name"])
        query = f"{record['name']} Yaounde"
        payload = search(query)

        if payload is None:
            failures += 1
            report(record, None, words)
        else:
            results = payload.get("results") or []
            if not results:
                empty += 1
            candidates.extend(report(record, results, words))

        time.sleep(PAUSE)

    print(f"\n{'=' * 70}")
    print(f"searched      : {len(targets)}")
    print(f"no results    : {empty}")
    print(f"search failed : {failures}  (unknown, not absent)")
    print(f"worth reading : {len(candidates)}")

    if candidates:
        print("\nThese share a distinctive word AND carry a shippable licence.")
        print("A shared word is not a match. Open each one and confirm the")
        print("picture is of that place before using it.\n")
        for record, result, overlap in candidates:
            print(f"  {record['id']}  {record['name']}")
            print(f"      {result.get('title')!r}  ({sorted(overlap)})")
            print(f"      {result.get('foreign_landing_url')}")
    elif not args.control:
        print("\nNothing to read. Run with --control to check the search")
        print("itself works before believing that.")


if __name__ == "__main__":
    main()
