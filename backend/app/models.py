"""
app/models.py

Data models and file I/O helpers.

All persistent data is stored in JSON files under the /data directory.
  - data/users.json       – registered users
  - data/itineraries.json – user itineraries
  - data/destinations.json – static destination catalogue (seed data)
  - data/shares.json      – shared itinerary records
"""
import json
import os

_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(_BASE_DIR, "data")

USERS_FILE = os.path.join(DATA_DIR, "users.json")
ITINERARIES_FILE = os.path.join(DATA_DIR, "itineraries.json")
DESTINATIONS_FILE = os.path.join(DATA_DIR, "destinations.json")
SHARES_FILE = os.path.join(DATA_DIR, "shares.json")


def _read_json(filepath: str) -> list:
    """Read a JSON file and return its contents as a Python list.

    Returns an empty list if the file does not exist or is empty.
    """
    if not os.path.exists(filepath):
        return []
    with open(filepath, "r", encoding="utf-8") as fh:
        content = fh.read().strip()
        if not content:
            return []
        return json.loads(content)


def _write_json(filepath: str, data: list) -> None:
    """Serialise *data* and write it to *filepath* (pretty-printed)."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)


# User helpers

def get_all_users() -> list:
    return _read_json(USERS_FILE)


def get_user_by_username(username: str) -> dict | None:
    users = get_all_users()
    for user in users:
        if user.get("username") == username:
            return user
    return None


def save_user(user: dict) -> None:
    users = get_all_users()
    users.append(user)
    _write_json(USERS_FILE, users)


# Destination helpers

def get_all_destinations() -> list:
    return _read_json(DESTINATIONS_FILE)


def get_destination_by_id(dest_id: str) -> dict | None:
    for dest in get_all_destinations():
        if dest.get("id") == dest_id:
            return dest
    return None


# Itinerary helpers

def get_all_itineraries() -> list:
    return _read_json(ITINERARIES_FILE)


def get_itineraries_for_user(username: str) -> list:
    return [it for it in get_all_itineraries() if it.get("username") == username]


def get_itinerary_by_id(itinerary_id: str) -> dict | None:
    for it in get_all_itineraries():
        if it.get("id") == itinerary_id:
            return it
    return None


def save_itinerary(itinerary: dict) -> None:
    itineraries = get_all_itineraries()
    itineraries.append(itinerary)
    _write_json(ITINERARIES_FILE, itineraries)


def update_itinerary(itinerary_id: str, updates: dict) -> dict | None:
    itineraries = get_all_itineraries()
    for idx, it in enumerate(itineraries):
        if it.get("id") == itinerary_id:
            updated = {**it, **updates}
            itineraries[idx] = updated
            _write_json(ITINERARIES_FILE, itineraries)
            return updated
    return None


def delete_itinerary(itinerary_id: str) -> bool:
    itineraries = get_all_itineraries()
    new_itineraries = [it for it in itineraries if it.get("id") != itinerary_id]
    if len(new_itineraries) == len(itineraries):
        return False
    _write_json(ITINERARIES_FILE, new_itineraries)
    return True


# Share helpers

def get_all_shares() -> list:
    return _read_json(SHARES_FILE)


def get_shares_for_itinerary(itinerary_id: str) -> list:
    return [s for s in get_all_shares() if s.get("itinerary_id") == itinerary_id]


def save_share(share: dict) -> None:
    shares = get_all_shares()
    shares.append(share)
    _write_json(SHARES_FILE, shares)


def delete_share(share_id: str) -> bool:
    shares = get_all_shares()
    new_shares = [s for s in shares if s.get("id") != share_id]
    if len(new_shares) == len(shares):
        return False
    _write_json(SHARES_FILE, new_shares)
    return True
