"""End-to-end checks for the live location endpoints.

Run from the backend directory:

    python tests/smoke_location.py

The suite runs against a throwaway DATA_DIR so it never touches real data. It
concentrates on the promises the feature makes about privacy — one record per
person, group-only visibility, expiry, and a delete that really deletes —
because those are the parts that would be damaging to get wrong.
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ["DATA_DIR"] = tempfile.mkdtemp(prefix="loc-smoke-")

from app import create_app, models  # noqa: E402

PASSWORD = "Tr@velSafe123"


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def sign_up(client, username: str) -> str:
    created = client.post("/api/auth/register", json={
        "username": username,
        "password": PASSWORD,
    })
    assert created.status_code == 201, created.get_json()
    signed_in = client.post("/api/auth/login", json={
        "username": username,
        "password": PASSWORD,
    })
    assert signed_in.status_code == 200, signed_in.get_json()
    return signed_in.get_json()["token"]


def main() -> None:
    client = create_app().test_client()

    # Anonymous callers learn nothing.
    assert client.get("/api/location/companions").status_code == 401
    assert client.put("/api/me/location", json={}).status_code == 401
    assert client.delete("/api/me/location").status_code == 401

    alice = sign_up(client, "alice")
    bob = sign_up(client, "bob")
    carol = sign_up(client, "carol")

    # Coordinates are validated rather than trusted.
    for payload in (
        {"latitude": 200, "longitude": 0},
        {"latitude": 3.8, "longitude": 500},
        {"latitude": "here", "longitude": 11.5},
        {"latitude": True, "longitude": 11.5},
        {"longitude": 11.5},
    ):
        rejected = client.put("/api/me/location", json=payload,
                              headers=auth(alice))
        assert rejected.status_code == 400, (payload, rejected.get_json())

    accepted = client.put(
        "/api/me/location",
        json={"latitude": 3.848, "longitude": 11.5021, "accuracy": 9.4},
        headers=auth(alice),
    )
    assert accepted.status_code == 200, accepted.get_json()

    # Repeated updates replace rather than accumulate: no trail is retained.
    for step in range(5):
        client.put(
            "/api/me/location",
            json={"latitude": 3.9 + step / 100, "longitude": 11.6},
            headers=auth(alice),
        )
    stored = models._read_json(models.LOCATIONS_FILE)
    assert len(stored) == 1, stored
    assert round(stored[0]["latitude"], 2) == 3.94, stored

    # Before any shared group, nobody can see Alice.
    for token in (bob, carol):
        body = client.get("/api/location/companions", headers=auth(token))
        assert body.get_json()["companions"] == [], body.get_json()

    # Alice and Bob share a room. Carol does not.
    rooms = models._read_json(models.CHAT_ROOMS_FILE)
    rooms.append({
        "id": "room-kribi",
        "name": "Kribi trip",
        "members": ["alice", "bob"],
        "type": "group",
    })
    models._write_json(models.CHAT_ROOMS_FILE, rooms)

    seen = client.get("/api/location/companions",
                      headers=auth(bob)).get_json()["companions"]
    assert [c["username"] for c in seen] == ["alice"], seen
    assert round(seen[0]["latitude"], 2) == 3.94, seen

    outsider = client.get("/api/location/companions",
                          headers=auth(carol)).get_json()["companions"]
    assert outsider == [], outsider

    # Nobody is ever listed to themselves, which would just be noise.
    own_view = client.get("/api/location/companions",
                          headers=auth(alice)).get_json()["companions"]
    assert own_view == [], own_view

    # An old position counts as no position, and is swept off disk on the next
    # write rather than lingering.
    stale = models._read_json(models.LOCATIONS_FILE)
    stale[0]["updated_at"] = "2001-01-01T00:00:00+00:00"
    models._write_json(models.LOCATIONS_FILE, stale)

    assert client.get("/api/location/companions",
                      headers=auth(bob)).get_json()["companions"] == []
    assert client.get("/api/me/location",
                      headers=auth(alice)).get_json()["location"] is None

    client.put("/api/me/location", json={"latitude": 4.0, "longitude": 9.7},
               headers=auth(bob))
    assert [r["username"] for r in models._read_json(models.LOCATIONS_FILE)] \
        == ["bob"], models._read_json(models.LOCATIONS_FILE)

    # Turning sharing off erases the record for real.
    erased = client.delete("/api/me/location", headers=auth(bob))
    assert erased.status_code == 200, erased.get_json()
    assert erased.get_json()["removed"] is True
    assert models._read_json(models.LOCATIONS_FILE) == []
    assert client.get("/api/location/companions",
                      headers=auth(alice)).get_json()["companions"] == []

    # Deleting again is harmless and honest about having found nothing.
    again = client.delete("/api/me/location", headers=auth(bob))
    assert again.status_code == 200 and again.get_json()["removed"] is False

    print("live location smoke test passed")


if __name__ == "__main__":
    main()
