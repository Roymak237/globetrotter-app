"""Fetch destination images from Wikimedia Commons with their licence intact.

Why this exists
---------------
``backend/data/destinations.json`` carries an ``image_attribution`` field for
every record, and 42 of the 54 entries currently read some variation of
"creator and license unverified". That string is an admission: we are shipping
files we cannot account for. This script closes that gap from the only source
that will actually answer the question — Wikimedia Commons, whose API returns
the author, the licence and the licence URL as structured metadata alongside
the file.

What it does NOT do
-------------------
It does not scrape. Every request goes through the public MediaWiki API with a
descriptive User-Agent, as the Wikimedia terms require, and every file it keeps
is one whose licence permits reuse. Files under a non-free or unknown licence
are rejected outright rather than downloaded and hoped about.

Usage
-----
    python scripts/fetch_destination_images.py --plan      # show, change nothing
    python scripts/fetch_destination_images.py --apply     # download + rewrite
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DESTINATIONS = REPO / "backend" / "data" / "destinations.json"
ASSET_ROOT = REPO / "frontend" / "assets" / "images"

API = "https://commons.wikimedia.org/w/api.php"

# Wikimedia asks every automated client to identify itself and give a contact
# point. A generic urllib agent gets rate-limited or blocked, and rightly so.
USER_AGENT = (
    "GlobetrotterApp/1.0 (https://kamer-go.duckdns.org; "
    "destination image sourcing) Python-urllib"
)

# Licences that permit redistribution in a commercial app, provided we credit.
# Anything not on this list is rejected rather than guessed at. "Fair use" and
# "non-commercial" variants are deliberately absent: they would not survive a
# store review.
ALLOWED_LICENCES = (
    "cc0",
    "cc by",
    "cc by-sa",
    "cc-by",
    "cc-by-sa",
    "public domain",
    "pd",
)

# Requested width. The app renders these as cards and hero images; anything
# beyond this is bytes the user pays for and never sees.
TARGET_WIDTH = 1200

# Commons has plenty of maps, coats of arms and scanned documents that match a
# place name but are useless as a photograph. Skipping them here is cheaper
# than noticing in review.
REJECT_TITLE_PATTERNS = re.compile(
    r"\b(map|carte|coat of arms|blason|flag|drapeau|logo|seal|"
    r"diagram|chart|graph|svg|icon|location|locator)\b",
    re.IGNORECASE,
)

ALLOWED_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp")


def clean_url(url: str) -> str:
    """Strip the analytics parameters the API staples onto image URLs.

    ``iiurlwidth`` responses come back carrying ``utm_source``,
    ``utm_campaign`` and ``utm_content``. Storing those in our data would
    mean every device that ever falls back to the remote copy reports itself
    to Wikimedia's campaign tracking, which is not something the app should
    be doing on a user's behalf. The bare URL serves the identical bytes.
    """
    parts = urllib.parse.urlsplit(url)
    kept = [
        (key, value)
        for key, value in urllib.parse.parse_qsl(parts.query)
        if not key.lower().startswith("utm_")
    ]
    # thumb.wikimedia.org is a valid alias but upload.wikimedia.org is the
    # host every other URL in this repository already uses. Keeping one host
    # means one TLS session and one set of cache entries.
    netloc = "upload.wikimedia.org" if parts.netloc == "thumb.wikimedia.org" else parts.netloc
    return urllib.parse.urlunsplit(
        (parts.scheme, netloc, parts.path, urllib.parse.urlencode(kept), "")
    )


@dataclass
class Candidate:
    """One Commons file that survived the licence and subject filters."""

    title: str
    url: str
    author: str
    licence: str
    licence_url: str
    width: int
    height: int

    def attribution(self, known_author: str = "") -> str:
        """The credit line the UI shows under the photo.

        Commons leaves ``Artist`` empty on plenty of older uploads even when a
        human name is recorded elsewhere. Where the repository already holds a
        real name, that name is better than printing "Unknown author" over it.
        """
        author = self.author or known_author or "Unknown author"
        return f"{author} \u2014 Wikimedia Commons, {self.licence}"

    @property
    def extension(self) -> str:
        suffix = Path(urllib.parse.urlparse(self.url).path).suffix.lower()
        return suffix if suffix in ALLOWED_EXTENSIONS else ".jpg"


# "Emmanuel Taquet — Wikimedia Commons, CC BY-SA 3.0" -> "Emmanuel Taquet".
# Only used to rescue a name the API does not return; never to invent one.
_CREDIT_AUTHOR = re.compile(r"^(.*?)\s*\u2014\s*Wikimedia Commons", re.DOTALL)


def known_author(record: dict) -> str:
    """Pull a previously recorded author out of an attribution string."""
    text = (record.get("image_attribution") or "").strip()
    if not text or "unverified" in text.lower():
        return ""
    match = _CREDIT_AUTHOR.match(text)
    return match.group(1).strip() if match else ""


def _request(params: dict) -> dict:
    """Call the MediaWiki API and return parsed JSON."""
    params = {**params, "format": "json", "formatversion": "2"}
    url = f"{API}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def _strip_html(value: str) -> str:
    """Commons returns author as an HTML fragment with links in it."""
    text = re.sub(r"<[^>]+>", "", value or "")
    text = urllib.parse.unquote(text)
    return " ".join(text.split()).strip()


def _licence_allowed(licence: str) -> bool:
    lowered = (licence or "").strip().lower()
    if not lowered:
        return False
    # Reject explicit non-commercial and no-derivatives terms even if the
    # string also contains "cc by", because "CC BY-NC" starts with "cc by".
    if "nc" in lowered.split("-") or "noncommercial" in lowered:
        return False
    if "nd" in lowered.split("-") or "noderiv" in lowered:
        return False
    if "fair use" in lowered or "non-free" in lowered:
        return False
    return any(lowered.startswith(prefix) for prefix in ALLOWED_LICENCES)


def search_titles(query: str, limit: int = 12) -> list[str]:
    """Search the File: namespace for a place name."""
    try:
        data = _request(
            {
                "action": "query",
                "list": "search",
                "srsearch": query,
                "srnamespace": "6",
                "srlimit": str(limit),
            }
        )
    except Exception as error:  # network, rate limit, malformed JSON
        print(f"    search failed: {error}", file=sys.stderr)
        return []
    return [row["title"] for row in data.get("query", {}).get("search", [])]


def describe(titles: list[str]) -> list[Candidate]:
    """Resolve titles to candidates, dropping anything we cannot reuse."""
    if not titles:
        return []
    try:
        data = _request(
            {
                "action": "query",
                "titles": "|".join(titles[:30]),
                "prop": "imageinfo",
                "iiprop": "url|extmetadata|size",
                "iiurlwidth": str(TARGET_WIDTH),
            }
        )
    except Exception as error:
        print(f"    metadata failed: {error}", file=sys.stderr)
        return []

    found: list[Candidate] = []
    for page in data.get("query", {}).get("pages", []):
        title = page.get("title", "")
        info = (page.get("imageinfo") or [{}])[0]
        if not info:
            continue

        meta = info.get("extmetadata", {}) or {}
        licence = _strip_html(meta.get("LicenseShortName", {}).get("value", ""))
        if not _licence_allowed(licence):
            continue
        if REJECT_TITLE_PATTERNS.search(title):
            continue
        if Path(title).suffix.lower() not in ALLOWED_EXTENSIONS:
            continue

        # Prefer the scaled render so we are not pulling 8 MB originals.
        url = info.get("thumburl") or info.get("url", "")
        if not url:
            continue

        found.append(
            Candidate(
                title=title,
                url=clean_url(url),
                author=_strip_html(meta.get("Artist", {}).get("value", "")),
                licence=licence,
                licence_url=_strip_html(
                    meta.get("LicenseUrl", {}).get("value", "")
                ),
                width=int(info.get("thumbwidth") or info.get("width") or 0),
                height=int(info.get("thumbheight") or info.get("height") or 0),
            )
        )
    return found


def best_for(name: str, extra_terms: str = "") -> Candidate | None:
    """Find the most usable Commons photo for a place."""
    queries = [q for q in (f"{name} {extra_terms}".strip(), name) if q]
    seen: set[str] = set()
    pool: list[Candidate] = []
    for query in queries:
        titles = [t for t in search_titles(query) if t not in seen]
        seen.update(titles)
        pool.extend(describe(titles))
        time.sleep(0.4)  # be a polite API citizen
        if pool:
            break
    if not pool:
        return None
    # Landscape images at a usable size make better cards than tall crops.
    pool.sort(key=lambda c: (c.width >= c.height, c.width), reverse=True)
    return pool[0]


def title_from_upload_url(url: str) -> str:
    """Recover the Commons ``File:`` title from an upload.wikimedia.org URL.

    The records already point at specific files. When we only need a local
    copy, re-searching would be vandalism: it would swap a hand-picked photo
    for whatever the search ranked first. Resolving the title instead lets us
    re-fetch *that* file, at a proper size, with its credit confirmed.
    """
    path = urllib.parse.urlparse(url).path
    if "/commons/" not in path:
        return ""
    name = Path(path).name
    # Thumb URLs look like .../thumb/a/ab/Foo.jpg/1200px-Foo.jpg — the real
    # file name is the directory above, not the rendered thumbnail.
    if "/thumb/" in path:
        name = Path(path).parent.name
    name = urllib.parse.unquote(name)
    return f"File:{name}" if name else ""


def exact_file(url: str) -> Candidate | None:
    """Look up the file a record already references, keeping that choice."""
    title = title_from_upload_url(url)
    if not title:
        return None
    found = describe([title])
    return found[0] if found else None


def slugify(value: str) -> str:
    """A filename-safe form of a place name.

    Accents are folded rather than deleted. Stripping them outright turned
    "Ecole Nationale Superieure" into "cole-nationale-sup-rieure", because
    the leading E of "Ecole" only exists inside the accented character.
    """
    folded = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(c for c in folded if not unicodedata.combining(c))
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_only.lower()).strip("-")
    return slug or "destination"


def download(candidate: Candidate, target: Path) -> int:
    """Save the file and return the byte count written."""
    req = urllib.request.Request(
        candidate.url, headers={"User-Agent": USER_AGENT}
    )
    with urllib.request.urlopen(req, timeout=60) as response:
        payload = response.read()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)
    return len(payload)


def load_destinations() -> tuple[object, list[dict]]:
    raw = json.loads(DESTINATIONS.read_text(encoding="utf-8"))
    records = raw if isinstance(raw, list) else raw.get("destinations", raw)
    return raw, records


def needs_attention(record: dict) -> str:
    """Classify why a record wants work, or '' if it is fine.

    The distinction that matters is between a record whose *photo* is wrong
    and one whose *paperwork* is wrong. A hotlinked image with a real credit
    needs a local copy, not a different picture.
    """
    asset = (record.get("image_asset") or "").strip()
    url = (record.get("image_url") or "").strip()
    attribution = (record.get("image_attribution") or "").strip()
    unverified = "unverified" in attribution.lower()

    if not asset and not url:
        return "missing"
    if not asset and url:
        # Points at a specific Commons file already. Mirror that exact file.
        return "mirror"
    if unverified and url:
        # Local file of unknown provenance, but the record names a Commons
        # file we can verify and use instead.
        return "mirror"
    if unverified:
        return "unverified"
    return ""


REASON_TEXT = {
    "missing": "no image at all",
    "mirror": "needs a verified local copy of the file it already names",
    "unverified": "local file, licence unknown, no Commons reference",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="download files and rewrite destinations.json",
    )
    parser.add_argument(
        "--only",
        default="",
        help="comma-separated destination ids to restrict the run to",
    )
    parser.add_argument(
        "--mode",
        default="mirror",
        choices=["mirror", "search", "all"],
        help=(
            "mirror: only records that already name a Commons file — same "
            "photo, verified credit, local copy. search: only records with no "
            "Commons reference, where the match is a guess and must be "
            "reviewed. all: both. Defaults to mirror because that is the "
            "only set where the chosen photograph cannot change."
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="stop after this many records (0 = no limit)",
    )
    args = parser.parse_args()

    _, records = load_destinations()
    only = {s.strip() for s in args.only.split(",") if s.strip()}

    wanted = {
        "mirror": {"mirror"},
        "search": {"unverified", "missing"},
        "all": {"mirror", "unverified", "missing"},
    }[args.mode]

    targets = []
    for record in records:
        if only and record.get("id") not in only:
            continue
        reason = needs_attention(record)
        if reason and reason in wanted:
            targets.append((record, reason))

    if args.limit:
        targets = targets[: args.limit]

    print(
        f"mode={args.mode}: {len(targets)} of {len(records)} records selected\n"
    )

    resolved = 0
    for record, reason in targets:
        name = record.get("name", "?")
        print(f"  {record.get('id')}  {name}")
        print(f"    reason: {REASON_TEXT.get(reason, reason)}")

        candidate = None
        if reason == "mirror":
            # Keep the editor's choice of photograph. We are only here to get
            # a local copy and confirm the credit.
            candidate = exact_file((record.get("image_url") or "").strip())
            if candidate is None:
                print("    named file is not reusable — falling back to search")

        if candidate is None:
            city = record.get("city") or record.get("country") or "Cameroon"
            candidate = best_for(name, city)

        if candidate is None:
            print("    NO USABLE COMMONS FILE \u2014 leaving as is\n")
            continue

        credit = candidate.attribution(known_author(record))
        print(f"    found : {candidate.title}")
        print(f"    credit: {credit}")
        print(f"    size  : {candidate.width}x{candidate.height}")

        if args.apply:
            folder = slugify(record.get("category") or "destinations")
            relative = f"{folder}/{slugify(name)}{candidate.extension}"
            written = download(candidate, ASSET_ROOT / relative)
            record["image_asset"] = relative
            record["image_url"] = candidate.url
            record["image_attribution"] = credit
            print(f"    saved : {relative} ({written // 1024} KB)")
        resolved += 1
        print()

    print(f"{resolved} of {len(targets)} resolved")

    if args.apply and resolved:
        raw, _ = load_destinations()
        payload = records if isinstance(raw, list) else {**raw, "destinations": records}
        DESTINATIONS.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {DESTINATIONS.relative_to(REPO)}")
    elif not args.apply:
        print("\n(plan only — pass --apply to download and rewrite)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
