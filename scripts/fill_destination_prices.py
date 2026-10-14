"""Tidy two things in the destination dataset.

1. Four names still carry a "(filename identification)" suffix left over from the
   photo import. The suffix told us the record was named from its filename; that
   caveat already lives in each record's description and location_notes, so it
   does not belong in the display name.

2. The batch of venues added with the most recent photographs never had a price
   band set, so the app shows "Not available" for them. Fill those in using the
   bands the rest of the dataset already uses, keeping the same wording so it
   stays obvious these are indicative figures rather than surveyed prices.

Schools, the hospital and ENSTP keep a null price on purpose: a visitor day rate
does not apply to a campus, and their cost_notes say so.
"""

import json
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "backend" / "data" / "destinations.json"

SUFFIX = " (filename identification)"

MEAL = (6000, "per_meal", "Indicative cost of a sit-down meal for one. Menus were not surveyed.")
NIGHT_OUT = (5000, "per_visit", "Indicative spend for an evening out with a few drinks. Not a quoted price.")
HOTEL_MID = (25000, "per_night", "Indicative nightly rate for a mid-range room. Rates were not confirmed with the property.")
HOTEL_TOP = (90000, "per_night", "Indicative nightly rate for a room at this hotel. Confirm current rates when booking.")
GUESTHOUSE = (20000, "per_night", "Indicative nightly rate for a guest room. Rates were not confirmed with the property.")
MUSEUM = (2000, "per_visit", "Typical museum admission for one adult. Check current prices before travelling.")
SHOP = (0, "free", "Free to enter. Spending depends on your shopping.")

PRICES = {
    # Restaurants. Cosy Pool is listed on OpenStreetMap as a restaurant despite
    # the name, and its own description says so, so it is priced as a meal.
    "dest-yao-090": MEAL,
    "dest-yao-093": MEAL,
    "dest-yao-094": MEAL,
    "dest-yao-095": MEAL,
    "dest-yao-100": MEAL,
    "dest-yao-101": MEAL,
    "dest-yao-102": MEAL,
    "dest-yao-103": MEAL,
    "dest-yao-104": MEAL,
    "dest-yao-107": MEAL,
    "dest-yao-108": MEAL,
    "dest-yao-113": MEAL,
    "dest-yao-115": MEAL,
    # Bars and dance venues.
    "dest-yao-089": NIGHT_OUT,
    "dest-yao-099": NIGHT_OUT,
    "dest-yao-117": NIGHT_OUT,
    # Hotels. The Hilton sits well above the mid-range band, so quoting the mid
    # band for it would mislead.
    "dest-yao-096": HOTEL_TOP,
    "dest-yao-097": HOTEL_MID,
    "dest-yao-098": HOTEL_MID,
    "dest-yao-110": HOTEL_MID,
    "dest-yao-114": HOTEL_MID,
    "dest-yao-116": HOTEL_MID,
    # Guest residences.
    "dest-yao-111": GUESTHOUSE,
    "dest-yao-112": GUESTHOUSE,
    # Museum.
    "dest-yao-105": MUSEUM,
    # Supermarket: free to walk into.
    "dest-yao-106": SHOP,
}


def main() -> None:
    records = json.loads(DATA.read_text(encoding="utf-8"))
    by_id = {r["id"]: r for r in records}

    renamed = []
    for record in records:
        if record["name"].endswith(SUFFIX):
            record["name"] = record["name"][: -len(SUFFIX)].strip()
            renamed.append(record["name"])

    missing = sorted(set(PRICES) - set(by_id))
    if missing:
        raise SystemExit(f"Unknown ids in the price table: {missing}")

    priced = []
    for dest_id, (amount, basis, notes) in PRICES.items():
        record = by_id[dest_id]
        if record.get("avg_cost_per_day") is not None:
            raise SystemExit(f"{dest_id} already has a price; refusing to overwrite it.")
        record["avg_cost_per_day"] = amount
        record["cost_basis"] = basis
        record["cost_notes"] = notes
        priced.append(f"{dest_id} {record['name']}: {amount} {basis}")

    body = json.dumps(records, ensure_ascii=False, indent=2) + "\n"
    DATA.write_text(body, encoding="utf-8", newline="\r\n")

    print(f"Dropped the filename suffix from {len(renamed)} names:")
    for name in renamed:
        print(f"  {name}")
    print(f"\nFilled in {len(priced)} prices:")
    for line in priced:
        print(f"  {line}")

    still_null = [r["id"] for r in records if r.get("avg_cost_per_day") is None]
    print(f"\nStill priceless on purpose ({len(still_null)}): {', '.join(still_null)}")


if __name__ == "__main__":
    main()
