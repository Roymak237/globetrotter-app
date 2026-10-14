"""Delete the destinations that no photograph could be found for.

Ten independent searches of freely-licensed sources failed to find a
picture of any of these places, so they are being removed rather than
left in a file that nobody will ever come back to.

What this does:

  - deletes backend/data/destinations_pending_photos.json
  - deletes the docs/missing-photos.* checklist that described it
  - checks nothing else in the repo still points at the removed ids,
    because a dangling reference in an itinerary is a crash, not a
    cosmetic problem

The records themselves survive in git history. The last commit that
contained them is named in the output so they can be recovered with a
single command if a photograph ever turns up.

Run:  python scripts/drop_photoless_destinations.py [--apply]
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "backend" / "data" / "destinations.json"
PENDING = ROOT / "backend" / "data" / "destinations_pending_photos.json"
DOCS = [
    ROOT / "docs" / "missing-photos.md",
    ROOT / "docs" / "missing-photos.txt",
]

# Everywhere a destination id could plausibly be referenced.
SCAN = [
    ROOT / "backend" / "data" / "itineraries.json",
    ROOT / "backend" / "data" / "shares.json",
    ROOT / "backend" / "data" / "users.json",
    ROOT / "frontend" / "lib",
    ROOT / "frontend" / "test",
    ROOT / "backend" / "app",
]

ID_PATTERN = re.compile(r"dest-[a-z]+-\d+")


def referenced_ids(path: Path) -> set[str]:
    found: set[str] = set()
    files = [path] if path.is_file() else list(path.rglob("*"))
    for f in files:
        if not f.is_file() or f.suffix not in {".json", ".dart", ".py"}:
            continue
        try:
            found |= set(ID_PATTERN.findall(f.read_text(encoding="utf-8")))
        except UnicodeDecodeError:
            continue
    return found


def main() -> int:
    apply = "--apply" in sys.argv

    if not PENDING.exists():
        print("nothing parked - already removed")
        return 0

    parked = json.loads(PENDING.read_text(encoding="utf-8"))
    live = json.loads(DATA.read_text(encoding="utf-8"))
    doomed = {r["id"] for r in parked}
    live_ids = {r["id"] for r in live}

    print(f"destinations in the app : {len(live)}")
    print(f"to be deleted outright  : {len(doomed)}")

    # A reference to a record that will not exist is the real risk here.
    dangling: list[str] = []
    for target in SCAN:
        if not target.exists():
            continue
        for rid in sorted(referenced_ids(target) & doomed):
            dangling.append(f"{rid} referenced by {target.relative_to(ROOT)}")

    if dangling:
        print(f"\nBLOCKED: {len(dangling)} dangling reference(s)")
        for line in dangling:
            print(f"    {line}")
        print("\nFix these before deleting, or the app will ask for a "
              "destination that no longer exists.")
        return 1
    print("no other file references any of them")

    # Name the commit that still holds them, so this is reversible.
    try:
        sha = subprocess.run(
            ["git", "log", "-1", "--format=%H", "--", str(PENDING)],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        sha = ""
    if sha:
        print(f"\nlast commit holding them: {sha[:12]}")
        print(f"recover with: git show {sha[:12]}:"
              "backend/data/destinations_pending_photos.json")

    if not apply:
        print("\nreport only. re-run with --apply to delete.")
        return 0

    PENDING.unlink()
    print(f"\ndeleted {PENDING.relative_to(ROOT)}")
    for doc in DOCS:
        if doc.exists():
            doc.unlink()
            print(f"deleted {doc.relative_to(ROOT)}")

    # Sanity: the live catalogue must be untouched by this.
    after = json.loads(DATA.read_text(encoding="utf-8"))
    assert {r["id"] for r in after} == live_ids, "live catalogue changed"
    print(f"\n{len(after)} destinations remain, all with a photograph")
    print("now run: python scripts/verify_destination_images.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
