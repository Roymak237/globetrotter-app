"""HEAD-check every remote image URL in the destinations data.

Throttled and retried, because an unthrottled sweep gets 429s back and those
look exactly like dead links if you are not paying attention.
"""

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DATA = REPO / "backend/data/destinations.json"

HEADERS = {
    "User-Agent": (
        "GlobetrotterApp/1.0 (https://kamer-go.duckdns.org; link audit) "
        "Python-urllib"
    )
}

raw = json.loads(DATA.read_text(encoding="utf-8"))
records = raw if isinstance(raw, list) else raw.get("destinations", raw)

rows = [
    (record.get("id"), (record.get("image_url") or "").strip())
    for record in records
]
rows = [row for row in rows if row[1]]

broken = []
for identifier, url in rows:
    status = None
    for attempt in range(3):
        try:
            status = urllib.request.urlopen(
                urllib.request.Request(url, headers=HEADERS), timeout=25
            ).status
            break
        except urllib.error.HTTPError as error:
            status = error.code
            if status == 429:
                time.sleep(5 + attempt * 5)
                continue
            break
        except Exception as error:  # DNS, TLS, timeout
            status = str(error)[:50]
            break
    if status != 200:
        broken.append((identifier, status))
    time.sleep(1.5)

print(f"checked {len(rows)} remote urls")
print(f"broken : {len(broken)}")
for identifier, status in broken:
    print(f"   {identifier} -> {status}")
