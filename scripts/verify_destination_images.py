"""Check that every destination the app ships can actually show a picture.

Two things can go wrong and they are different:

  - a record with no image at all
  - a record naming an asset that is not on disk

The second is the nastier one, because the JSON looks fine. This checks
both, and also reports assets declared under a folder pubspec.yaml does
not bundle, which fails only at runtime.

Run:  python scripts/verify_destination_images.py
Exit code is non-zero if anything is wrong, so CI can use it.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "backend" / "data" / "destinations.json"
IMAGES = ROOT / "frontend" / "assets" / "images"
PUBSPEC = ROOT / "frontend" / "pubspec.yaml"


def bundled_prefixes() -> list[str]:
    """Asset folders and files pubspec.yaml actually ships."""
    text = PUBSPEC.read_text(encoding="utf-8")
    # Only the entries under the flutter: assets: list, which are the
    # lines beginning with a dash inside that block.
    block = re.search(r"\n  assets:\n((?:\s+[-#].*\n)+)", text)
    if not block:
        return []
    out = []
    for line in block.group(1).splitlines():
        line = line.strip()
        if line.startswith("- "):
            out.append(line[2:].strip())
    return out


def main() -> int:
    records = json.loads(DATA.read_text(encoding="utf-8"))
    prefixes = [p for p in bundled_prefixes() if p.startswith("assets/images")]

    no_image: list[str] = []
    missing_file: list[str] = []
    not_bundled: list[str] = []

    for rec in records:
        asset = rec.get("image_asset")
        url = rec.get("image_url")
        if not asset and not url:
            no_image.append(f"{rec['id']}  {rec['name']}")
            continue
        if not asset:
            continue

        path = IMAGES / asset
        if not path.is_file():
            missing_file.append(f"{rec['id']}  {rec['name']}  ->  {asset}")
            continue

        declared = f"assets/images/{asset}"
        folder = declared.rsplit("/", 1)[0] + "/"
        if folder not in prefixes and declared not in prefixes:
            not_bundled.append(f"{rec['id']}  {asset}  (needs {folder})")

        for extra in rec.get("additional_image_assets") or []:
            if not (IMAGES / extra).is_file():
                missing_file.append(f"{rec['id']}  extra  ->  {extra}")

    print(f"destinations            : {len(records)}")
    print(f"with no image           : {len(no_image)}")
    for line in no_image:
        print(f"    {line}")
    print(f"naming a missing file   : {len(missing_file)}")
    for line in missing_file:
        print(f"    {line}")
    print(f"in an unbundled folder  : {len(not_bundled)}")
    for line in sorted(set(not_bundled)):
        print(f"    {line}")

    bad = len(no_image) + len(missing_file) + len(not_bundled)
    print("\nOK" if bad == 0 else f"\n{bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
