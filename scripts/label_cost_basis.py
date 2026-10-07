"""Label every price with what it actually buys.

The detail screen shows one tile headed "EST. DAILY COST". For 50 of the
53 priced records that heading is wrong: 2000 XAF against the National
Museum is one adult's admission, not a day's spending, and the note
underneath says so while the tile above contradicts it.

Rather than guess a basis per record, this reads the basis out of the
sentence already written for each one. Those sentences were authored by
hand and reviewed; they are the better source.
"""
import json
import re
from pathlib import Path

DATA = Path("backend/data/destinations.json")

# Ordered: the first pattern that matches a note wins, so the more
# specific phrasings are listed before the general ones.
RULES = [
    ("per_night", r"\bnightly rate\b"),
    ("per_day", r"\bdaily (budget|cost)\b|\bper day\b|\bday-pass\b"),
    ("per_meal", r"\bsit-down meal\b|\bmeal for one\b"),
    ("per_visit", r"\badmission\b|\bentry\b|\bentrance\b"),
    ("per_visit", r"\bafternoon of play\b"),
    ("per_trip", r"\bboat trip\b|\bsite access\b|\blocal access\b"),
    ("per_day", r"\bguided climb\b"),
]


def basis_for(record):
    """What the figure on this record buys, or "" when there is none."""
    cost = record.get("avg_cost_per_day")
    if cost is None:
        return "none"
    if cost == 0:
        return "free"
    note = (record.get("cost_notes") or "").lower()
    for basis, pattern in RULES:
        if re.search(pattern, note):
            return basis
    return "unclassified"


def main():
    records = json.loads(DATA.read_text(encoding="utf-8"))

    counts = {}
    unclassified = []
    for record in records:
        basis = basis_for(record)
        counts[basis] = counts.get(basis, 0) + 1
        if basis == "unclassified":
            unclassified.append(record)
        record["cost_basis"] = basis

    for basis, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {basis:14} {n}")

    if unclassified:
        print(f"\n{len(unclassified)} notes matched no rule:")
        for record in unclassified:
            print(f"  {record['avg_cost_per_day']:>6}  {record['name'][:34]:34}"
                  f" | {record['cost_notes'][:58]}")
        print("\nnothing written: every priced record needs a basis")
        return 1

    DATA.write_text(
        json.dumps(records, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"\nwrote {DATA}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
