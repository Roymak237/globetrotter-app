"""Report how unmatched image files relate to destination records.

restore_destination.py matches on an exact squashed name. That is
deliberately strict - a wrong match puts the wrong photo on a place,
which is worse than no photo. But when nothing matches it is useless
for working out why, so this reports the near misses instead.

Scores every image file against every record, live and parked, using
token overlap plus a containment bonus, and prints the best few. It
changes nothing; it is for reading.

Run:  python scripts/match_images_report.py
"""

from __future__ import annotations

import json
import sys
from difflib import SequenceMatcher
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prune_photoless_destinations import (  # noqa: E402
    DATA,
    IMAGES,
    PENDING,
    USABLE,
    squash,
)

# Words that say nothing about which place this is. Leaving them in
# makes every restaurant look similar to every other restaurant.
NOISE = {
    "yaounde",
    "yde",
    "cameroun",
    "cameroon",
    "hotel",
    "restaurant",
    "resto",
    "le",
    "la",
    "les",
    "de",
    "du",
    "des",
    "d",
    "l",
    "the",
    "et",
    "a",
    "au",
    "aux",
    "en",
    "chez",
    "1",
    "2",
    "3",
}


def tokens(text: str) -> set[str]:
    raw = squash_words(text)
    kept = {w for w in raw if w not in NOISE and len(w) > 1}
    # If stripping noise leaves nothing, the noise *was* the name.
    return kept or raw


def squash_words(text: str) -> set[str]:
    import re
    import unicodedata

    plain = unicodedata.normalize("NFKD", text)
    plain = plain.encode("ascii", "ignore").decode("ascii").lower()
    return {w for w in re.split(r"[^a-z0-9]+", plain) if w}


def score(image_stem: str, name: str) -> float:
    a, b = tokens(image_stem), tokens(name)
    if not a or not b:
        return 0.0
    overlap = len(a & b) / len(a | b)
    # A record name wholly contained in the filename is a strong signal:
    # "Le safoutier restaurant" contains all of "Le Safoutier".
    containment = 1.0 if b <= a or a <= b else 0.0
    ratio = SequenceMatcher(None, squash(image_stem), squash(name)).ratio()
    return max(overlap, containment * 0.95, ratio * 0.8)


def main() -> int:
    live = json.loads(DATA.read_text(encoding="utf-8"))
    parked = json.loads(PENDING.read_text(encoding="utf-8")) if PENDING.exists() else []

    # A file used only as a gallery extra is still spoken for.
    claimed = {r["image_asset"] for r in live if r.get("image_asset")}
    claimed |= {
        extra
        for r in live
        for extra in (r.get("additional_image_assets") or [])
    }
    pool = [("live", r) for r in live] + [("parked", r) for r in parked]

    files = [
        p
        for p in IMAGES.rglob("*")
        if p.is_file() and p.suffix.lower() in USABLE
    ]
    loose = [
        p
        for p in files
        if p.relative_to(IMAGES).as_posix() not in claimed
        and p.parent == IMAGES  # top-level drops are the new ones
    ]

    print(f"image files total      : {len(files)}")
    print(f"unclaimed at top level : {len(loose)}")
    print()

    for path in sorted(loose, key=lambda p: p.name.lower()):
        stem = path.stem
        ranked = sorted(
            ((score(stem, r["name"]), where, r) for where, r in pool),
            key=lambda t: -t[0],
        )[:3]
        print(f"{path.name}")
        for s, where, r in ranked:
            if s < 0.30:
                continue
            print(f"    {s:.2f}  [{where:6}] {r['id']}  {r['name']}")
        if all(s < 0.30 for s, _, _ in ranked):
            print("    (no candidate above 0.30 - probably a new place)")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
