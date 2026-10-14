"""Drop destinations that have no photograph; adopt any photo already on disk.

The rule the app should satisfy: every destination it shows has a
picture. This script enforces that rule rather than asserting it.

Two passes:

1. Adopt. Any photoless record whose name matches a file already sitting
   under frontend/assets/images gets wired up. Matching is on a squashed
   form of the name (lowercase, accents stripped, punctuation dropped),
   so "Yaounde Grand Mosque.webp" finds "Yaounde Grand Mosque" and
   "Marche aux Bestiaux.jpg" would find "Marché aux Bestiaux".

2. Quarantine. Whatever is still photoless moves out of
   destinations.json and into destinations_pending_photos.json.

Quarantine rather than delete, because each of those records carries an
address, verified coordinates, a cost, a cost basis and hand-written
notes. Deleting throws that away; a photo arriving later would mean
redoing it. Git history holds it too, but a file you can read beats a
commit you have to go digging for.

Run:  python scripts/prune_photoless_destinations.py [--apply]

Without --apply it reports and changes nothing.
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "backend" / "data" / "destinations.json"
PENDING = ROOT / "backend" / "data" / "destinations_pending_photos.json"
IMAGES = ROOT / "frontend" / "assets" / "images"

# What Flutter will actually decode. A .heic or .tiff in the folder is
# not a usable asset, so it must not count as "has a photo".
USABLE = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}


def squash(text: str) -> str:
    """Lowercase, de-accented, alphanumerics only.

    Used on both sides of the match so filename punctuation and the
    record's accents cannot cause a miss.
    """
    plain = unicodedata.normalize("NFKD", text)
    plain = plain.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", "", plain.lower())


def index_images() -> dict[str, str]:
    """Map squashed filename stem -> path relative to assets/images."""
    found: dict[str, str] = {}
    for path in IMAGES.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in USABLE:
            continue
        rel = path.relative_to(IMAGES).as_posix()
        key = squash(path.stem)
        if not key:
            continue
        # First writer wins, so a deliberate destinations/foo.jpg is not
        # shadowed by an incidental foo.jpg dropped elsewhere later.
        found.setdefault(key, rel)
    return found


def main() -> int:
    apply = "--apply" in sys.argv

    records = json.loads(DATA.read_text(encoding="utf-8"))
    images = index_images()

    photoless = [
        r for r in records if not r.get("image_asset") and not r.get("image_url")
    ]

    adopted: list[tuple[str, str, str]] = []
    for rec in photoless:
        key = squash(rec["name"])
        rel = images.get(key)
        if rel is None:
            continue
        rec["image_asset"] = rel
        # Honest about provenance. The existing records that claim
        # "creator and license unverified" are a known wart; do not
        # quietly invent a licence for these.
        rec["image_attribution"] = (
            "Supplied by the project maintainer. "
            "Source and licence not yet recorded."
        )
        adopted.append((rec["id"], rec["name"], rel))

    still_photoless = [
        r for r in records if not r.get("image_asset") and not r.get("image_url")
    ]
    removed_ids = {r["id"] for r in still_photoless}
    keeping = [r for r in records if r["id"] not in removed_ids]

    print(f"records before        : {len(records)}")
    print(f"photoless at start    : {len(photoless)}")
    print(f"adopted from assets   : {len(adopted)}")
    for rid, name, rel in adopted:
        print(f"    {rid}  {name}  ->  {rel}")
    print(f"quarantined           : {len(still_photoless)}")
    print(f"records after         : {len(keeping)}")

    if not apply:
        print("\nreport only. re-run with --apply to write.")
        return 0

    # Merge with anything already quarantined so repeated runs do not
    # drop earlier entries.
    previous = []
    if PENDING.exists():
        previous = json.loads(PENDING.read_text(encoding="utf-8"))
    seen = {r["id"] for r in still_photoless}
    merged = still_photoless + [r for r in previous if r["id"] not in seen]
    merged.sort(key=lambda r: r["id"])

    DATA.write_text(
        json.dumps(keeping, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    PENDING.write_text(
        json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"\nwrote {DATA}")
    print(f"wrote {PENDING}  ({len(merged)} awaiting a photo)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
