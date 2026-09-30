"""Report which images on disk are unused and which destinations lack one."""
import json
from pathlib import Path

IMAGES = Path("frontend/assets/images")

destinations = json.loads(
    Path("backend/data/destinations.json").read_text(encoding="utf-8"))

referenced = set()
for dest in destinations:
    if dest.get("image_asset"):
        referenced.add(dest["image_asset"].replace("\\", "/"))
    for extra in dest.get("additional_image_assets") or []:
        if extra:
            referenced.add(extra.replace("\\", "/"))

on_disk = {
    str(path.relative_to(IMAGES)).replace("\\", "/")
    for path in IMAGES.rglob("*")
    if path.is_file()
}

print("referenced but missing from disk:")
for asset in sorted(referenced - on_disk):
    print(f"  {asset}")

print("\non disk but unused:")
for asset in sorted(on_disk - referenced):
    print(f"  {asset}")

print("\ndestinations with no photo at all:")
for dest in destinations:
    if not dest.get("image_asset") and not dest.get("image_url"):
        print(f"  {dest['id']}  {dest['name']}")
