"""Add Yaounde destinations from OpenStreetMap, with real coordinates.

Why OpenStreetMap
-----------------
``destinations.json`` already refuses to carry a coordinate it cannot
source: nine records deliberately have no pin and say so to the user
("We only know this venue is in Yaounde, so there is no map pin yet").
An earlier pass in this repo learned the hard way that a confident wrong
pin is worse than an absent one — Nominatim once resolved "Yaounde" to a
railway station and Mvog-Betsi park to a civil-engineering hangar.

So nothing here is invented. Every record this script emits is a real
OpenStreetMap object: its coordinates are that object's geometry, and its
``location_sources`` entry is a link to the object itself, so any pin can
be checked rather than trusted.

What it will not do
-------------------
It will not write a description containing a fact that is not in the OSM
tags. No opening hours it did not read, no "cosy atmosphere", no made-up
speciality. Where OSM records a cuisine or a denomination, the description
says so and says where it came from. Where OSM records nothing beyond the
name and the type, the description says only that.

It attaches no images. The photographs in this repo carry a licence and a
photographer, and there is no licensed photo of a corner restaurant in
Yaounde. An empty image field falls through to the category icon, which is
honest; a borrowed photo would not be.

Usage
-----
    python scripts/add_osm_destinations.py --plan
    python scripts/add_osm_destinations.py --apply --count 50
"""

from __future__ import annotations

import argparse
import json
import math
import re
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DATA = REPO / "backend" / "data" / "destinations.json"

# The main instance throttles and times out under load. These are the
# public mirrors that run the same API; rotating across them spreads the
# cost rather than hammering one donated server until it gives up.
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.osm.jp/api/interpreter",
]
USER_AGENT = (
    "kamer-go-destination-survey/1.0 (capstone project; contact via repo)"
)

# Yaounde's urban area, as south,west,north,east. Deliberately generous,
# because the bounding box is a cheap first filter; CITY_CENTRE and
# MAX_KM_FROM_CENTRE below do the real work of deciding what counts as
# "in Yaounde".
BBOX = "3.75,11.40,3.99,11.62"

# Place de l'Independance, give or take. The box above reaches Soa, which
# is a university town 14 km north-east and not part of Yaounde; a request
# for places in Yaounde should not quietly return places near Yaounde.
CITY_CENTRE = (3.8687, 11.5213)
MAX_KM_FROM_CENTRE = 12.0

CACHE_DIR = REPO / ".git" / "osm_cache"


# --------------------------------------------------------------------------
# Category definitions
#
# The left-hand key is the tag the destinations screen filters on; see
# _typeFilters in frontend/lib/screens/destinations_screen.dart. Adding a
# category here that the UI does not filter on would produce records nobody
# can find.
# --------------------------------------------------------------------------
CATEGORIES = {
    "dining": {
        "selectors": [
            'nwr["amenity"="restaurant"]["name"]',
            'nwr["amenity"="cafe"]["name"]',
            'nwr["amenity"="fast_food"]["name"]',
        ],
        "tags": ["dining", "food", "restaurant"],
        "cost": 6000,
        "cost_notes": "Indicative cost of a sit-down meal for one. Menus were not surveyed.",
        "want": 10,
    },
    "gaming": {
        "selectors": [
            'nwr["leisure"="amusement_arcade"]["name"]',
            'nwr["amenity"="internet_cafe"]["name"]',
        ],
        "tags": ["gaming", "entertainment"],
        "cost": 3000,
        "cost_notes": "Indicative spend for an afternoon of play. Not a quoted price.",
        "want": 5,
    },
    "shopping": {
        "selectors": [
            'nwr["shop"="supermarket"]["name"]',
            'nwr["shop"="mall"]["name"]',
            'nwr["amenity"="marketplace"]["name"]',
            'nwr["shop"="department_store"]["name"]',
        ],
        "tags": ["shopping", "retail"],
        "cost": 0,
        "cost_notes": "Free to enter. Spending depends on your shopping.",
        "want": 7,
    },
    "education": {
        "selectors": [
            'nwr["amenity"="university"]["name"]',
            'nwr["amenity"="college"]["name"]',
            'nwr["amenity"="library"]["name"]',
        ],
        "tags": ["education", "school"],
        "cost": None,
        "cost_notes": "A daily visitor cost does not apply to a campus. Contact the institution about tuition.",
        "want": 6,
    },
    "tourist": {
        "selectors": [
            'nwr["tourism"="museum"]["name"]',
            'nwr["tourism"="attraction"]["name"]',
            'nwr["tourism"="artwork"]["name"]',
            'nwr["tourism"="viewpoint"]["name"]',
        ],
        "tags": ["tourist", "culture"],
        "cost": 2000,
        "cost_notes": "Typical admission for one adult. Check current prices before travelling.",
        "want": 6,
    },
    "landmark": {
        "selectors": [
            'nwr["historic"="monument"]["name"]',
            'nwr["historic"="memorial"]["name"]',
            'nwr["amenity"="place_of_worship"]["name"]["building"]',
        ],
        "tags": ["landmark", "history"],
        "cost": 0,
        "cost_notes": "Outdoor landmarks are normally free to view.",
        "want": 6,
    },
    "leisure": {
        "selectors": [
            'nwr["leisure"="park"]["name"]',
            'nwr["leisure"="garden"]["name"]',
            'nwr["amenity"="cinema"]["name"]',
            'nwr["amenity"="theatre"]["name"]',
        ],
        "tags": ["leisure", "relaxation"],
        "cost": 1000,
        "cost_notes": "Indicative entry for a public park. Some are free.",
        "want": 5,
    },
    "recreation": {
        "selectors": [
            'nwr["leisure"="sports_centre"]["name"]',
            'nwr["leisure"="stadium"]["name"]',
            'nwr["leisure"="fitness_centre"]["name"]',
            'nwr["leisure"="swimming_pool"]["name"]',
            'nwr["leisure"="pitch"]["name"]',
        ],
        "tags": ["recreation", "sport"],
        "cost": 0,
        "cost_notes": "Free to use where public. Clubs and pools may charge.",
        "want": 5,
    },
}

# OSM amenity/leisure/shop value -> plain English for the description.
KIND_WORDS = {
    "restaurant": "restaurant",
    "cafe": "cafe",
    "fast_food": "fast-food outlet",
    "amusement_arcade": "games arcade",
    "internet_cafe": "internet cafe",
    "supermarket": "supermarket",
    "mall": "shopping mall",
    "marketplace": "market",
    "department_store": "department store",
    "university": "university",
    "college": "college",
    "library": "library",
    "museum": "museum",
    "attraction": "visitor attraction",
    "artwork": "public artwork",
    "viewpoint": "viewpoint",
    "monument": "monument",
    "memorial": "memorial",
    "place_of_worship": "place of worship",
    "park": "public park",
    "garden": "garden",
    "cinema": "cinema",
    "theatre": "theatre",
    "sports_centre": "sports centre",
    "stadium": "stadium",
    "fitness_centre": "gym",
    "swimming_pool": "swimming pool",
    "pitch": "sports pitch",
}

# Names that identify nothing. OSM carries plenty of these; a destination
# called "Boutique" helps nobody find anything.
GENERIC_NAMES = re.compile(
    r"^(restaurant|bar|boutique|snack|shop|magasin|cafe|caf\u00e9|hotel|"
    r"school|ecole|\u00e9cole|college|coll\u00e8ge|lyc\u00e9e|lycee|"
    r"supermarket|market|march\u00e9|marche|pharmacie|pharmacy|station|"
    r"complexe|centre|center|salle|kiosque|call box|callbox)$",
    re.IGNORECASE,
)


def overpass(query: str, attempts: int = 6) -> dict:
    """POST a query, rotating mirrors and backing off on overload.

    429 means we asked too fast and 504 means the instance is saturated;
    both clear given a pause or a different mirror. A 400 is our own bug and
    retrying it just wastes someone else's capacity.
    """
    delay = 4
    last = ""
    for attempt in range(attempts):
        endpoint = ENDPOINTS[attempt % len(ENDPOINTS)]
        data = urllib.parse.urlencode({"data": query}).encode()
        request = urllib.request.Request(
            endpoint, data=data, headers={"User-Agent": USER_AGENT}
        )
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            detail = " ".join(error.read().decode("utf-8", "replace").split())
            last = f"HTTP {error.code}"
            if error.code not in (429, 504, 503):
                raise RuntimeError(f"{last}: {detail[:160]}") from None
        except Exception as error:  # socket timeout, reset connection
            last = type(error).__name__
        if attempt < attempts - 1:
            time.sleep(delay)
            delay = min(delay * 2, 40)
    raise RuntimeError(last)


def cached_query(name: str, query: str, force: bool = False) -> list[dict]:
    """Run a query once and keep the answer on disk.

    Per-category files rather than one blob, so a single failed category
    costs one retry instead of refetching everything that already worked.
    """
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = CACHE_DIR / f"{name}.json"
    if path.exists() and not force:
        return json.loads(path.read_text(encoding="utf-8"))

    print(f"  querying {name} ...", end=" ", flush=True)
    try:
        elements = overpass(query).get("elements", [])
    except RuntimeError as error:
        print(f"FAILED {error}")
        return []
    path.write_text(json.dumps(elements), encoding="utf-8")
    print(f"{len(elements)} elements")
    time.sleep(2)
    return elements


def fetch_all(force: bool = False) -> dict:
    """Fetch candidates one category at a time, caching as we go.

    A single query covering all 28 selectors timed out the public endpoint.
    Asking in smaller pieces, with a pause between them, is both more
    reliable and better behaved than one enormous request.
    """
    merged: dict[tuple[str, int], dict] = {}
    missing = []
    for name, spec in CATEGORIES.items():
        body = "".join(
            f"{selector}({BBOX});" for selector in spec["selectors"]
        )
        query = f"[out:json][timeout:120];({body});out center tags;"
        elements = cached_query(name, query, force)
        if not elements:
            missing.append(name)
        for element in elements:
            merged[(element["type"], element["id"])] = element

    if missing:
        print(f"  NO DATA for: {', '.join(missing)}")
    print(f"  {len(merged)} unique elements")
    return {"elements": list(merged.values()), "missing": missing}


def fetch_places() -> list[dict]:
    """Fetch Yaounde's named areas so a pin can say which one it is in.

    Cameroon's OSM data tags most of Yaounde's quarters as place=village —
    Nkolbisson, Simbock and Mfandena are all real quarters of the city
    carrying that tag. Excluding them left 10 usable nodes and almost every
    description reading "in Yaounde", which is true but useless. They are
    included, and the distance limit does the work instead.
    """
    query = (
        f"[out:json][timeout:90];"
        f'(node["place"~"^(suburb|neighbourhood|quarter|village|town|city)$"]["name"]({BBOX}););'
        f"out;"
    )
    elements = cached_query("quarters", query)
    return [
        {
            "name": element["tags"]["name"],
            "lat": element["lat"],
            "lon": element["lon"],
        }
        for element in elements
        if element.get("tags", {}).get("name")
        and "lat" in element
        and element["tags"].get("place")
        in ("suburb", "neighbourhood", "quarter", "village", "town")
    ]


def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in kilometres."""
    radius = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return 2 * radius * math.asin(math.sqrt(a))


def usable_quarter(name: str) -> bool:
    """Reject place names that look like a stray POI rather than a quarter.

    Yaounde's quarters are mapped in title case — Nkolbisson, Simbock,
    Mfandena. A node shouting "EBOGO CITY" in the middle of the university
    district is somebody's development marketing, and attaching it to four
    unrelated listings as their "area" would spread one bad node across the
    whole dataset.
    """
    stripped = name.strip()
    if len(stripped) < 3:
        return False
    letters = [c for c in stripped if c.isalpha()]
    if letters and all(c.isupper() for c in letters):
        return False
    return normalise(stripped) not in CITY_ALIASES


def nearest_quarter(lat: float, lon: float, places: list[dict]) -> tuple[str, float]:
    best_name, best_distance = "", 1e9
    for place in places:
        if not usable_quarter(place["name"]):
            continue
        distance = haversine(lat, lon, place["lat"], place["lon"])
        if distance < best_distance:
            best_name, best_distance = place["name"], distance
    return best_name, best_distance


def resolve_quarter(
    tags: dict, lat: float, lon: float, places: list[dict]
) -> str:
    """Name the quarter a place is in, or say nothing.

    The POI's own address tags win: a mapper standing outside the building
    knows its quarter better than any distance calculation. Failing that,
    the nearest named area within 1.5 km, which the measured distribution
    puts at roughly the 75th percentile — so three POIs in four get a name
    and the outliers honestly get none.
    """
    for key in ("addr:suburb", "addr:quarter", "addr:neighbourhood"):
        value = (tags.get(key) or "").strip()
        if value and usable_quarter(value):
            return value

    name, distance = nearest_quarter(lat, lon, places)
    return name if distance <= 1.5 else ""


def coordinates_of(element: dict) -> tuple[float, float] | None:
    """A node carries its own position; a way or relation carries a centre."""
    if "lat" in element and "lon" in element:
        return element["lat"], element["lon"]
    centre = element.get("center")
    if centre:
        return centre["lat"], centre["lon"]
    return None


def classify(tags: dict) -> tuple[str, str] | None:
    """Return (category key, OSM kind) for an element, or None."""
    checks = [
        ("amenity", tags.get("amenity")),
        ("leisure", tags.get("leisure")),
        ("shop", tags.get("shop")),
        ("tourism", tags.get("tourism")),
        ("historic", tags.get("historic")),
    ]
    for key, spec in CATEGORIES.items():
        wanted = set()
        for selector in spec["selectors"]:
            match = re.search(r'"(amenity|leisure|shop|tourism|historic)"="([^"]+)"', selector)
            if match:
                wanted.add((match.group(1), match.group(2)))
        for field, value in checks:
            if value and (field, value) in wanted:
                return key, value
    return None


def fold(text: str) -> str:
    """Strip accents so French and English spellings can be compared.

    Without this, normalise() deleted accented letters outright and turned
    "r\u00e9unification" into "runification", which matches nothing. Decomposing
    first turns it into "reunification", which matches the English name of
    the same monument.
    """
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c))


def normalise(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", fold(name).lower())


# Words too common in place names to prove two records are the same place.
# Quarter names get added at runtime: "Marche Mvog-Betsi" and "Mvog-Betsi
# Zoo" share a word, but it is the name of the neighbourhood they both sit
# in, which the distance check has already established and which says
# nothing about whether they are the same place.
STOPWORDS = {
    "de", "du", "des", "la", "le", "les", "of", "the", "and", "et", "a",
    "yaounde", "cameroun", "cameroon", "centre", "center", "central",
    "saint", "st", "place", "rue", "avenue", "boulevard", "quartier",
    "college", "ecole", "school", "universite", "university", "institut",
    "institute", "eglise", "church", "restaurant", "hotel", "bar", "club",
    "market", "marche", "super", "supermarket", "boutique", "complexe",
}


def distinctive_words(name: str, extra_stopwords: frozenset[str] = frozenset()) -> set[str]:
    """The words in a name that actually identify a specific place."""
    words = re.findall(r"[a-z0-9]+", fold(name).lower())
    return {
        w
        for w in words
        if len(w) >= 5 and w not in STOPWORDS and w not in extra_stopwords
    }


# Written against normalise(), so accents and punctuation do not matter.
CITY_ALIASES = {"yaounde", "yaound", "yaoundeville", "yaoundei", "centre"}


def readable_list(values: list[str]) -> str:
    """Join with commas and a final 'and', the way a person would write it."""
    values = [v for v in values if v]
    if len(values) <= 1:
        return values[0] if values else ""
    return f"{', '.join(values[:-1])} and {values[-1]}"


def article(word: str) -> str:
    """Pick "a" or "an" by sound rather than by spelling.

    "An university" is what a pure vowel check produces. The words that
    matter here start with a consonant /j/ sound despite the vowel letter.
    """
    lowered = word.lower()
    if lowered.startswith(("uni", "use", "eu", "one")):
        return "A"
    return "An" if lowered[:1] in "aeiou" else "A"


# operator=private and friends are classifications, not names. "Operated by
# private" is noise; worse, it reads as though we know who runs the place.
JUNK_OPERATORS = {
    "private", "public", "state", "government", "prive", "privé",
    "yes", "no", "unknown", "none", "laic", "laïc", "confessionnel",
}

# Banks get mapped onto the shop node that happens to host their ATM, so a
# supermarket ends up "operated by afriland first banque". Attributing the
# claim to OSM does not make it less wrong on the page, so drop it.
FINANCE_WORDS = (
    "bank", "banque", "bancaire", "assurance", "insurance",
    "microfinance", "finance", "credit", "crédit", "mutuelle",
)
RETAIL_KINDS = {
    "supermarket", "convenience", "marketplace", "department_store",
    "mall", "bakery", "restaurant", "cafe", "fast_food", "bar", "pub",
}


def usable_operator(value: str, name: str, kind: str = "") -> bool:
    """True when an operator tag names an actual organisation.

    OSM carries operator values like "2-0 mballa 2", which is a plot
    reference rather than a company. If it has no run of letters in it, it
    is not a name anybody would recognise.
    """
    value = (value or "").strip()
    if not value or value.lower() in JUNK_OPERATORS:
        return False
    if not re.search(r"[A-Za-z\u00c0-\u017f]{3,}", value):
        return False
    folded = fold(value)
    if kind in RETAIL_KINDS and any(w in folded for w in FINANCE_WORDS):
        return False
    return normalise(value) not in normalise(name)


def build_description(name: str, kind: str, quarter: str, tags: dict) -> str:
    """Describe the place using only what OSM actually records.

    Every clause below traces to a tag, and the classification is attributed
    rather than asserted. That matters: OSM tags a chess club as an
    amusement arcade, so stating "a games arcade" as our own claim would be
    wrong in a way that "listed on OpenStreetMap as" is not.
    """
    word = KIND_WORDS.get(kind, kind.replace("_", " "))
    where = f"in the {quarter} area of Yaounde" if quarter else "in Yaounde"
    sentence = f"{article(word)} {word} {where}, as listed on OpenStreetMap."

    extras = []
    cuisine = tags.get("cuisine")
    if cuisine:
        extras.append(
            "serves "
            + readable_list(
                [
                    part.replace("_", " ").strip()
                    for part in cuisine.split(";")[:3]
                ]
            )
        )

    denomination = tags.get("denomination") or tags.get("religion")
    if denomination and kind == "place_of_worship":
        extras.append(
            f"belongs to the {denomination.replace('_', ' ')} tradition"
        )

    sport = tags.get("sport")
    if sport:
        extras.append(
            "is used for "
            + readable_list(
                [s.replace("_", " ") for s in sport.split(";")[:3]]
            )
        )

    operator = tags.get("operator")
    if operator and usable_operator(operator, name, kind):
        extras.append(f"is operated by {operator.strip()}")

    if extras:
        sentence += " The same entry says it " + readable_list(extras) + "."

    sentence += (
        " Opening hours and prices were not checked for this listing, so"
        " confirm them locally before travelling."
    )
    return sentence


def osm_url(element: dict) -> str:
    return f"https://www.openstreetmap.org/{element['type']}/{element['id']}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--count", type=int, default=50)
    parser.add_argument("--refresh", action="store_true", help="ignore cache")
    parser.add_argument(
        "--dump",
        default="",
        help="write the full proposed records to this file for review",
    )
    args = parser.parse_args()

    records = json.loads(DATA.read_text(encoding="utf-8"))
    existing_names = {normalise(r["name"]) for r in records}
    existing_sources = {
        source
        for record in records
        for source in (record.get("location_sources") or [])
    }
    # Name matching alone misses the same place recorded in another
    # language: OSM's "Musee National" sits 21 metres from the record this
    # repository calls "National Museum".
    #
    # Only exact pins take part. Nineteen records carry an "area" pin that
    # marks a neighbourhood centre, not a building; colliding against those
    # deleted a real restaurant for standing near the city-centre marker.
    #
    # 60 m is where the measured curve flattens: 40 m catches 18 candidates,
    # 60 m catches 19, and 80 m jumps to 22. The plateau is the boundary
    # between "same plot" and "same street".
    existing_points = [
        (r["latitude"], r["longitude"], r["name"])
        for r in records
        if r.get("latitude")
        and r.get("longitude")
        and r.get("location_precision") == "exact"
    ]

    def collides(lat: float, lon: float, name: str) -> str:
        words = distinctive_words(name, place_words)
        for other_lat, other_lon, other_name in existing_points:
            metres = haversine(lat, lon, other_lat, other_lon) * 1000
            if metres <= 60:
                return other_name
            # "Place de la reunification" sits 62 m from the record called
            # "Reunification Monument" — two metres outside the radius and
            # unmistakably the same square. Where the names share a word
            # that identifies the place, allow a wider margin.
            #
            # 150 m rather than 300: not every shared word is a business
            # name. "Mvog-Betsi" is a quarter that OSM has not mapped as a
            # place node, so the market and the zoo appear to share an
            # identity when they only share an address. The asymmetry
            # favours skipping — there are 443 dining candidates for 10
            # slots, so a missed one costs nothing, while a duplicate on
            # the screen costs the user.
            if metres <= 150 and words & distinctive_words(other_name, place_words):
                return other_name
        return ""

    raw = fetch_all(force=args.refresh)
    places = fetch_places()

    # Every word that is the name of a quarter cannot also be evidence that
    # two businesses are the same business.
    place_words = frozenset(
        word
        for place in places
        for word in re.findall(r"[a-z0-9]+", fold(place["name"]).lower())
        if len(word) >= 4
    )

    # Group candidates by category, rejecting anything we cannot stand behind.
    buckets: dict[str, list[dict]] = {key: [] for key in CATEGORIES}
    duplicates: list[str] = []
    outside = 0
    for element in raw.get("elements", []):
        tags = element.get("tags") or {}
        name = (tags.get("name") or "").strip()
        if not name or len(name) < 4 or GENERIC_NAMES.match(name):
            continue
        if normalise(name) in existing_names:
            continue
        if osm_url(element) in existing_sources:
            continue

        position = coordinates_of(element)
        if position is None:
            continue

        # "In Yaounde" has to mean in Yaounde. The bounding box reaches
        # satellite towns; this does not.
        if (
            haversine(position[0], position[1], *CITY_CENTRE)
            > MAX_KM_FROM_CENTRE
        ):
            outside += 1
            continue

        classified = classify(tags)
        if classified is None:
            continue
        category, kind = classified

        duplicate = collides(position[0], position[1], name)
        if duplicate:
            duplicates.append(f"{name} ~ {duplicate}")
            continue

        # Accepted candidates join the collision set. Without this the batch
        # happily proposed "MATECO Complexe Sportif de l'Universite de
        # Yaounde 1" and "MATECO Complexe Sportif de l'Universite" as two
        # destinations, because each was only ever compared against the
        # records already in the file.
        existing_points.append((position[0], position[1], name))

        quarter = resolve_quarter(tags, position[0], position[1], places)

        # A richer OSM entry is a better-maintained one. This is a proxy for
        # whether a human has looked at it recently, not for quality.
        detail = sum(
            1
            for key in ("cuisine", "website", "phone", "opening_hours",
                        "operator", "addr:street", "sport", "denomination")
            if tags.get(key)
        )

        buckets[category].append(
            {
                "element": element,
                "name": name,
                "kind": kind,
                "quarter": quarter,
                "tags": tags,
                "position": position,
                "detail": detail,
            }
        )
        existing_names.add(normalise(name))

    print()
    if outside:
        print(f"  skipped {outside} outside {MAX_KM_FROM_CENTRE:.0f} km of the city centre")
    if duplicates:
        print(f"  skipped {len(duplicates)} as duplicates of existing records:")
        for line in duplicates[:8]:
            print(f"    {line}")
    for category, items in buckets.items():
        items.sort(key=lambda c: (c["detail"], len(c["name"])), reverse=True)
        print(f"  {category:12} {len(items):4} candidates "
              f"(want {CATEGORIES[category]['want']})")

    # Take the per-category quota first, then top up round-robin rather than
    # by raw score. Sorting the leftovers globally handed 21 of 50 slots to
    # dining purely because OSM has more restaurants than parks, which is a
    # fact about OSM and not about what someone visiting Yaounde wants.
    chosen: list[dict] = []
    remaining: dict[str, list[dict]] = {}
    for category, spec in CATEGORIES.items():
        take = buckets[category][: spec["want"]]
        chosen.extend(dict(c, category=category) for c in take)
        remaining[category] = buckets[category][spec["want"]:]

    while len(chosen) < args.count and any(remaining.values()):
        progressed = False
        for category in CATEGORIES:
            if len(chosen) >= args.count:
                break
            if remaining[category]:
                chosen.append(dict(remaining[category].pop(0), category=category))
                progressed = True
        if not progressed:
            break
    chosen = chosen[: args.count]

    # Continue the existing id sequence rather than restarting it.
    used = {
        int(m.group(1))
        for r in records
        if (m := re.match(r"dest-yao-(\d+)$", r["id"]))
    }
    next_id = max(used) + 1 if used else 1

    built = []
    for candidate in chosen:
        spec = CATEGORIES[candidate["category"]]
        element = candidate["element"]
        latitude, longitude = candidate["position"]
        quarter = candidate["quarter"]

        address = (
            f"{quarter}, Yaounde, Centre, Cameroon"
            if quarter
            else "Yaounde, Centre, Cameroon"
        )
        street = candidate["tags"].get("addr:street")
        if street:
            address = f"{street}, {address}"

        record = {
            "id": f"dest-yao-{next_id:03d}",
            "name": candidate["name"],
            "region": "Centre",
            "description": build_description(
                candidate["name"], candidate["kind"], quarter, candidate["tags"]
            ),
            "tags": list(spec["tags"]),
            "avg_cost_per_day": spec["cost"],
            "highlights": [],
            "image_url": "",
            "image_asset": "",
            "image_attribution": "",
            "address": address,
            "location_notes": (
                "The pin comes from this venue's OpenStreetMap entry, linked"
                " below, so it can be checked against the source."
            ),
            "location_sources": [osm_url(element)],
            "additional_image_assets": [],
            "latitude": round(latitude, 6),
            "longitude": round(longitude, 6),
            "location_precision": "exact",
            "cost_notes": spec["cost_notes"],
        }
        built.append(record)
        next_id += 1

    print(f"\nselected {len(built)} new destinations")
    by_category: dict[str, int] = {}
    for candidate in chosen:
        by_category[candidate["category"]] = by_category.get(candidate["category"], 0) + 1
    for category, count in sorted(by_category.items()):
        print(f"  {category:12} {count}")

    if args.dump:
        lines = []
        for record, candidate in zip(built, chosen):
            lines.append(
                f"[{candidate['category']}] {record['id']}  {record['name']}"
            )
            lines.append(f"    {record['description']}")
            lines.append(f"    addr : {record['address']}")
            lines.append(
                f"    pin  : {record['latitude']}, {record['longitude']}"
            )
            lines.append(f"    src  : {record['location_sources'][0]}")
            lines.append("")
        Path(args.dump).write_text("\n".join(lines), encoding="utf-8")
        print(f"dumped {len(built)} records to {args.dump}")

    if args.apply:
        records.extend(built)
        DATA.write_text(
            json.dumps(records, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"\nwrote {DATA.relative_to(REPO)} \u2014 now {len(records)} records")
    else:
        print("\n(plan only \u2014 pass --apply to write)")
        for record in built[:5]:
            print(f"\n  {record['id']}  {record['name']}")
            print(f"    {record['description']}")
            print(f"    {record['latitude']}, {record['longitude']}")
            print(f"    {record['location_sources'][0]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
