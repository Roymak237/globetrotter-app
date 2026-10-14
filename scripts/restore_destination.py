"""Move parked destinations back into the app once a photo shows up.

The counterpart to prune_photoless_destinations.py. Reads
destinations_pending_photos.json, looks for a matching image file under
frontend/assets/images, and moves any record that now has one back into
destinations.json.

Matching is on a squashed form of the name - lowercase, accents
stripped, punctuation dropped - so the file can be called
"Marche aux Bestiaux.jpg" or "marche-aux-bestiaux.webp" and either is
found. Drop it anywhere under assets/images; subfolders are searched.

Run:  python scripts/restore_destination.py [--apply]
      python scripts/restore_destination.py --apply dest-yao-043

Without --apply it reports and changes nothing. Record ids may be given
to restrict the run.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# Reuse the matcher so adopt-on-prune and adopt-on-restore can never
# disagree about what counts as a match.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from prune_photoless_destinations import (  # noqa: E402
    DATA,
    IMAGES,
    PENDING,
    index_images,
    squash,
)


def main() -> int:
    argv = sys.argv[1:]
    apply = "--apply" in argv
    only = {a for a in argv if a.startswith("dest-")}

    if not PENDING.exists():
        print(f"nothing parked: {PENDING} does not exist")
        return 0

    parked = json.loads(PENDING.read_text(encoding="utf-8"))
    live = json.loads(DATA.read_text(encoding="utf-8"))
    images = index_images()

    # Assets already claimed by a live record, so two destinations cannot
    # silently end up sharing one photo.
    claimed = {r["image_asset"] for r in live if r.get("image_asset")}

    restored: list[dict] = []
    still_parked: list[dict] = []
    collisions: list[str] = []

    for rec in parked:
        if only and rec["id"] not in only:
            still_parked.append(rec)
            continue
        rel = images.get(squash(rec["name"]))
        if rel is None:
            still_parked.append(rec)
            continue
        if rel in claimed:
            collisions.append(f"{rec['id']}  {rec['name']}  wants {rel}, taken")
            still_parked.append(rec)
            continue
        rec["image_asset"] = rel
        rec["image_attribution"] = (
            "Supplied by the project maintainer. "
            "Source and licence not yet recorded."
        )
        claimed.add(rel)
        restored.append(rec)

    print(f"parked before   : {len(parked)}")
    print(f"found a photo   : {len(restored)}")
    for rec in restored:
        print(f"    {rec['id']}  {rec['name']}  ->  {rec['image_asset']}")
    if collisions:
        print(f"name collisions : {len(collisions)}")
        for line in collisions:
            print(f"    {line}")
    print(f"still parked    : {len(still_parked)}")

    if not restored:
        print("\nno files matched. check the name against docs/missing-photos.md")
        return 0
    if not apply:
        print("\nreport only. re-run with --apply to write.")
        return 0

    merged = live + restored
    merged.sort(key=lambda r: r["id"])

    DATA.write_text(
        json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    PENDING.write_text(
        json.dumps(still_parked, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"\nwrote {DATA}  ({len(merged)} destinations)")
    print(f"wrote {PENDING}  ({len(still_parked)} still awaiting a photo)")
    print("\nnow run: python scripts/verify_destination_images.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
