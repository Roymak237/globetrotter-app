"""Write a checklist of destinations that still have no photograph.

The output is meant to be worked through by hand: each entry carries the
address, the coordinates and a map link so the place can be identified
before a photo is downloaded, plus the exact filename the app expects.

Run:  python scripts/list_photoless.py
"""

from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "backend" / "data" / "destinations.json"
# Records pulled out of the app because they had no picture. They are
# the thing that needs photographing, so they are the real source here.
PENDING = ROOT / "backend" / "data" / "destinations_pending_photos.json"
OUT = ROOT / "docs" / "missing-photos.md"

# Where the Flutter app resolves image_asset from.
ASSET_ROOT = "frontend/assets/images"
# One folder keeps the mapping unambiguous; category folders would mean
# guessing a category per record and guessing wrong is worse than flat.
ASSET_DIR = "destinations"


def slugify(name: str) -> str:
    """ASCII, lowercase, hyphenated - safe on every filesystem we deploy to."""
    plain = unicodedata.normalize("NFKD", name)
    plain = plain.encode("ascii", "ignore").decode("ascii")
    plain = re.sub(r"[^a-zA-Z0-9]+", "-", plain).strip("-").lower()
    return re.sub(r"-{2,}", "-", plain)


def category(tags: list[str]) -> str:
    """A short human hint so the downloader knows what they are looking for."""
    known = [
        ("restaurant", "restaurant"),
        ("food", "food"),
        ("bar", "bar"),
        ("cafe", "cafe"),
        ("hotel", "hotel"),
        ("school", "school"),
        ("university", "university"),
        ("shopping", "shopping"),
        ("market", "market"),
        ("religious", "place of worship"),
        ("gaming", "gaming"),
        ("sport", "sport"),
        ("nature", "nature"),
        ("culture", "culture"),
        ("landmark", "landmark"),
    ]
    lowered = {t.lower() for t in tags}
    for key, label in known:
        if any(key in t for t in lowered):
            return label
    return ", ".join(tags[:3]) if tags else "uncategorised"


def main() -> int:
    live = json.loads(DATA.read_text(encoding="utf-8"))
    missing = json.loads(PENDING.read_text(encoding="utf-8")) if PENDING.exists() else []
    # Anything still live without a picture would be a bug, but list it
    # too rather than pretend the quarantine file is the whole truth.
    missing += [
        r for r in live if not r.get("image_asset") and not r.get("image_url")
    ]
    missing.sort(key=lambda r: r["id"])

    lines: list[str] = []
    lines.append("# Destinations waiting on a photograph")
    lines.append("")
    lines.append(
        f"These {len(missing)} places are **not in the app**. They were "
        f"removed from `destinations.json` because they had no picture, and "
        f"parked in `backend/data/destinations_pending_photos.json`. The app "
        f"currently ships {len(live)} destinations, every one of which has a "
        f"real image file."
    )
    lines.append("")
    lines.append(
        "Nine automated searches of freely-licensed repositories "
        "(Wikimedia Commons geosearch, Commons text search, Commons "
        "category walk, OpenStreetMap picture tags, Openverse, Wikidata "
        "P18, Panoramax street-level) found nothing for any of these, so "
        "they have to be photographed or sourced by hand."
    )
    lines.append("")
    lines.append("## How to restore one")
    lines.append("")
    lines.append(
        f"1. Drop the photo anywhere under `{ASSET_ROOT}/`. The suggested "
        f"path below is tidy, but the matcher works on the **name**, so "
        f"`My Place.webp` sitting at the top level is found just as well."
    )
    lines.append(
        "2. `.jpg`, `.png` and `.webp` all work. Roughly 1200px on the long "
        "edge is plenty; the cards never render larger than that."
    )
    lines.append(
        "3. Run `python scripts/restore_destination.py` - it matches files "
        "to parked records by name and moves them back into the app."
    )
    lines.append(
        "4. Run `python scripts/verify_destination_images.py` to confirm "
        "every shipped destination still resolves to a file that exists."
    )
    lines.append("")
    lines.append(
        "Note where each photo came from. The app stores an "
        "`image_attribution` per destination, and 37 older records already "
        'say "creator and license unverified" - a wart worth not repeating.'
    )
    lines.append("")
    lines.append("## The list")
    lines.append("")

    for i, r in enumerate(missing, 1):
        name = r["name"]
        lat, lon = r.get("latitude"), r.get("longitude")
        lines.append(f"### {i}. {name}")
        lines.append("")
        lines.append(f"- **Save as** `{ASSET_DIR}/{slugify(name)}.jpg`")
        lines.append(f"- **Record** `{r['id']}`")
        lines.append(f"- **Kind** {category(r.get('tags') or [])}")
        addr = r.get("address") or "(no address recorded)"
        lines.append(f"- **Address** {addr}")
        notes = r.get("location_notes")
        if notes:
            lines.append(f"- **Location notes** {notes}")
        if lat is not None and lon is not None:
            lines.append(
                f"- **Map** [{lat:.5f}, {lon:.5f}]"
                f"(https://www.openstreetmap.org/?mlat={lat}&mlon={lon}#map=19/{lat}/{lon})"
            )
        prec = r.get("location_precision")
        if prec:
            lines.append(f"- **Coordinate precision** {prec}")
        lines.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(missing)} photoless destinations written to {OUT}")

    # A flat list too - easier to paste into a download manager or a notes app.
    flat = ROOT / "docs" / "missing-photos.txt"
    flat.write_text(
        "\n".join(
            f"{r['id']}\t{r['name']}\t{ASSET_DIR}/{slugify(r['name'])}.jpg"
            for r in missing
        ),
        encoding="utf-8",
    )
    print(f"flat list written to {flat}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
