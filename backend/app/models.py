"""
app/models.py

Data models and database helpers.

All persistent data is stored in a SQLite database at /data/globetrotter.db.
"""
import json
import os
import sqlite3
from datetime import datetime

_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(_BASE_DIR, "data")
DB_PATH = os.path.join(DATA_DIR, "globetrotter.db")


def _get_connection():
    """Return a row-factory SQLite connection."""
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    """Create database tables if they do not exist and seed static data."""
    os.makedirs(DATA_DIR, exist_ok=True)
    conn = _get_connection()
    cursor = conn.cursor()

    cursor.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            preferences TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS destinations (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            region TEXT NOT NULL,
            description TEXT,
            tags TEXT,
            avg_cost_per_day REAL,
            highlights TEXT,
            image_url TEXT
        );
        CREATE TABLE IF NOT EXISTS itineraries (
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL,
            title TEXT NOT NULL,
            destinations TEXT,
            start_date TEXT,
            end_date TEXT,
            notes TEXT,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS shares (
            id TEXT PRIMARY KEY,
            itinerary_id TEXT NOT NULL,
            owner TEXT NOT NULL,
            shared_with TEXT NOT NULL,
            created_at TEXT
        );
    """)

    conn.commit()

    # Seed destinations if table is empty
    cursor.execute("SELECT COUNT(*) as cnt FROM destinations")
    if cursor.fetchone()["cnt"] == 0:
        dest_path = os.path.join(DATA_DIR, "destinations.json")
        if os.path.exists(dest_path):
            with open(dest_path, "r", encoding="utf-8") as fh:
                destinations = json.load(fh)
            for dest in destinations:
                cursor.execute(
                    """INSERT INTO destinations
                    (id, name, region, description, tags, avg_cost_per_day, highlights, image_url)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        dest["id"],
                        dest["name"],
                        dest["region"],
                        dest["description"],
                        json.dumps(dest.get("tags", [])),
                        dest.get("avg_cost_per_day"),
                        json.dumps(dest.get("highlights", [])),
                        dest.get("image_url", ""),
                    ),
                )
            conn.commit()

    conn.close()


# User helpers

def get_all_users():
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users")
    rows = cursor.fetchall()
    conn.close()
    users = []
    for row in rows:
        user = dict(row)
        user["preferences"] = json.loads(user.get("preferences") or "[]")
        users.append(user)
    return users


def get_user_by_username(username: str) -> dict | None:
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE username = ?", (username,))
    row = cursor.fetchone()
    conn.close()
    if row:
        user = dict(row)
        user["preferences"] = json.loads(user.get("preferences") or "[]")
        return user
    return None


def save_user(user: dict) -> None:
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO users (id, username, password_hash, preferences, created_at) VALUES (?, ?, ?, ?, ?)",
        (
            user["id"],
            user["username"],
            user["password_hash"],
            json.dumps(user.get("preferences", [])),
            datetime.now(datetime.utcnow().tzinfo).isoformat(),
        ),
    )
    conn.commit()
    conn.close()


# Destination helpers

def get_all_destinations():
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM destinations")
    rows = cursor.fetchall()
    conn.close()
    destinations = []
    for row in rows:
        d = dict(row)
        d["tags"] = json.loads(d.get("tags") or "[]")
        d["highlights"] = json.loads(d.get("highlights") or "[]")
        destinations.append(d)
    return destinations


def get_destination_by_id(dest_id: str) -> dict | None:
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM destinations WHERE id = ?", (dest_id,))
    row = cursor.fetchone()
    conn.close()
    if row:
        d = dict(row)
        d["tags"] = json.loads(d.get("tags") or "[]")
        d["highlights"] = json.loads(d.get("highlights") or "[]")
        return d
    return None


# Itinerary helpers

def get_all_itineraries():
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM itineraries")
    rows = cursor.fetchall()
    conn.close()
    itineraries = []
    for row in rows:
        it = dict(row)
        it["destinations"] = json.loads(it.get("destinations") or "[]")
        itineraries.append(it)
    return itineraries


def get_itineraries_for_user(username: str) -> list:
    return [it for it in get_all_itineraries() if it.get("username") == username]


def get_itinerary_by_id(itinerary_id: str) -> dict | None:
    for it in get_all_itineraries():
        if it.get("id") == itinerary_id:
            return it
    return None


def save_itinerary(itinerary: dict) -> None:
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO itineraries
        (id, username, title, destinations, start_date, end_date, notes, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            itinerary["id"],
            itinerary["username"],
            itinerary["title"],
            json.dumps(itinerary.get("destinations", [])),
            itinerary.get("start_date", ""),
            itinerary.get("end_date", ""),
            itinerary.get("notes", ""),
            itinerary.get("created_at"),
        ),
    )
    conn.commit()
    conn.close()


def update_itinerary(itinerary_id: str, updates: dict) -> dict | None:
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM itineraries WHERE id = ?", (itinerary_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        return None
    current = dict(row)
    current["destinations"] = json.loads(current.get("destinations") or "[]")
    updated = {**current, **updates}
    if "destinations" in updates and isinstance(updates["destinations"], list):
        updated["destinations"] = updates["destinations"]
    cursor.execute(
        """UPDATE itineraries SET
        title = ?, destinations = ?, start_date = ?, end_date = ?, notes = ?
        WHERE id = ?""",
        (
            updated["title"],
            json.dumps(updated.get("destinations", [])),
            updated.get("start_date", ""),
            updated.get("end_date", ""),
            updated.get("notes", ""),
            itinerary_id,
        ),
    )
    conn.commit()
    conn.close()
    return updated


def delete_itinerary(itinerary_id: str) -> bool:
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM itineraries WHERE id = ?", (itinerary_id,))
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


# Share helpers

def get_all_shares():
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM shares")
    rows = cursor.fetchall()
    conn.close()
    return [dict(row) for row in rows]


def get_shares_for_itinerary(itinerary_id: str) -> list:
    return [s for s in get_all_shares() if s.get("itinerary_id") == itinerary_id]


def save_share(share: dict) -> None:
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO shares (id, itinerary_id, owner, shared_with, created_at) VALUES (?, ?, ?, ?, ?)",
        (
            share["id"],
            share["itinerary_id"],
            share["owner"],
            share["shared_with"],
            share["created_at"],
        ),
    )
    conn.commit()
    conn.close()


def delete_share(share_id: str) -> bool:
    conn = _get_connection()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM shares WHERE id = ?", (share_id,))
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    return deleted
