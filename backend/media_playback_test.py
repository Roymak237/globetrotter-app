"""Checks for the media playback path.

The Flutter player asks for a playback ticket before opening any audio or
video attachment, because a ``<video>`` element cannot carry an
Authorization header. That route did not exist, so every video and every
voice note failed to open while images - which are fetched with an
explicit bearer token instead - kept working. Nothing noticed, because
nothing exercised the path end to end.

These run against the real Flask app with a temporary data directory.

Run:  python backend/media_playback_test.py
"""

from __future__ import annotations

import io
import os
import struct
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))

PASSED = 0
FAILED = 0


def check(label: str, condition: bool, detail: str = "") -> None:
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  PASS  {label}")
    else:
        FAILED += 1
        print(f"  FAIL  {label}" + (f"\n          {detail}" if detail else ""))


def tiny_mp4() -> bytes:
    """Smallest thing that looks like an MP4 to a type sniffer.

    The bytes never reach a decoder in these tests; what matters is the
    ``ftyp`` box so upload type-detection behaves as it would in life.
    """
    ftyp = b"ftypisom" + struct.pack(">I", 512) + b"isomiso2mp41"
    return struct.pack(">I", len(ftyp) + 4) + ftyp + b"\x00" * 2048


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="kamergo-media-test-")
    # models.py reads DATA_DIR. Getting this name wrong does not fail loudly;
    # it silently writes test users and test uploads into the real data
    # directory, which is exactly what happened the first time this ran.
    os.environ["DATA_DIR"] = tmp

    from app.main import create_app  # imported after the env var is set

    app = create_app()
    app.config["SECRET_KEY"] = "test-secret-for-media-checks"
    client = app.test_client()

    print("\nregistering a user")
    reg = client.post(
        "/api/auth/register",
        json={
            "username": "mediatester",
            "email": "media@example.com",
            "password": "Str0ng!Passw0rd",
        },
    )
    token = None
    if reg.status_code in (200, 201):
        token = reg.get_json().get("token")
    if not token:
        login = client.post(
            "/api/auth/login",
            json={"username": "mediatester", "password": "Str0ng!Passw0rd"},
        )
        token = (login.get_json() or {}).get("token")
    check("obtained a session token", bool(token), f"register said {reg.status_code}")
    if not token:
        return 1
    auth = {"Authorization": f"Bearer {token}"}

    print("\nuploading a video attachment")
    upload = client.post(
        "/api/media",
        headers=auth,
        data={"file": (io.BytesIO(tiny_mp4()), "clip.mp4", "video/mp4")},
        content_type="multipart/form-data",
    )
    check("upload accepted", upload.status_code == 201, str(upload.get_json()))
    if upload.status_code != 201:
        return 1
    body = upload.get_json()
    file_id = body["id"]
    check("classified as video", body["kind"] == "video", f"got {body['kind']}")
    check("stored with an .mp4 name", file_id.endswith(".mp4"), file_id)

    print("\nplayback ticket")
    # This is the exact call MediaService.playbackTicket makes.
    ticket_response = client.post(f"/api/media/{file_id}/ticket", headers=auth)
    check(
        "the route the player calls exists",
        ticket_response.status_code == 200,
        f"POST /api/media/<id>/ticket returned {ticket_response.status_code}",
    )
    if ticket_response.status_code != 200:
        return 1
    ticket_body = ticket_response.get_json()
    check("response carries a url", "url" in ticket_body, str(ticket_body))
    check("response carries expires_in", "expires_in" in ticket_body, str(ticket_body))
    check(
        "url points at this file",
        ticket_body.get("url", "").startswith(f"/api/media/{file_id}?"),
        ticket_body.get("url", ""),
    )

    print("\nticket authentication")
    check(
        "an anonymous caller is refused",
        client.post(f"/api/media/{file_id}/ticket").status_code == 401,
    )
    check(
        "a ticket for a missing file is a 404",
        client.post("/api/media/deadbeef.mp4/ticket", headers=auth).status_code
        == 404,
    )

    print("\nplaying the file back")
    played = client.get(ticket_body["url"])
    check("ticketed fetch succeeds", played.status_code == 200, str(played.status_code))
    check(
        "served as video/mp4, which a <video> element will accept",
        played.headers.get("Content-Type", "").startswith("video/mp4"),
        played.headers.get("Content-Type", ""),
    )
    check(
        "advertises byte ranges so the player can seek",
        played.headers.get("Accept-Ranges") == "bytes",
        played.headers.get("Accept-Ranges", "(absent)"),
    )

    print("\nrange request")
    ranged = client.get(ticket_body["url"], headers={"Range": "bytes=0-99"})
    check(
        "a range request returns 206 Partial Content",
        ranged.status_code == 206,
        str(ranged.status_code),
    )
    check(
        "and returns exactly the bytes asked for",
        len(ranged.data) == 100,
        f"got {len(ranged.data)} bytes",
    )

    print("\nticket validation")
    check(
        "a forged ticket is refused",
        client.get(f"/api/media/{file_id}?ticket=not-a-real-token").status_code
        == 403,
    )
    # A ticket minted for one file must not unlock another.
    other = client.post(
        "/api/media",
        headers=auth,
        data={"file": (io.BytesIO(tiny_mp4()), "other.mp4", "video/mp4")},
        content_type="multipart/form-data",
    ).get_json()
    stolen = ticket_body["url"].split("ticket=")[1]
    check(
        "a ticket for one file does not unlock another",
        client.get(f"/api/media/{other['id']}?ticket={stolen}").status_code == 403,
    )
    check(
        "an expired ticket is refused",
        _expired_ticket_is_refused(app, client, file_id),
    )

    print("\nvoice notes use the same path")
    audio = client.post(
        "/api/media",
        headers=auth,
        data={"file": (io.BytesIO(b"ID3" + b"\x00" * 2048), "note.mp3", "audio/mpeg")},
        content_type="multipart/form-data",
    )
    check("audio upload accepted", audio.status_code == 201, str(audio.get_json()))
    if audio.status_code == 201:
        audio_id = audio.get_json()["id"]
        check(
            "a voice note can also obtain a ticket",
            client.post(f"/api/media/{audio_id}/ticket", headers=auth).status_code
            == 200,
        )
        served = client.get(f"/api/media/{audio_id}")
        check(
            "served as audio/mpeg",
            served.headers.get("Content-Type", "").startswith("audio/mpeg"),
            served.headers.get("Content-Type", ""),
        )

    print("\nimages still work without a ticket")
    check(
        "an unticketed fetch is still allowed, as <img> needs",
        client.get(f"/api/media/{file_id}").status_code == 200,
    )

    print(f"\n{PASSED}/{PASSED + FAILED} checks passed")
    return 1 if FAILED else 0


def _expired_ticket_is_refused(app, client, file_id: str) -> bool:
    """Mint a ticket that expired in the past and confirm it is rejected."""
    import datetime

    import jwt

    past = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(
        seconds=10
    )
    stale = jwt.encode(
        {
            "sub": "mediatester",
            "fid": file_id,
            "iat": past - datetime.timedelta(seconds=300),
            "exp": past,
        },
        app.config["SECRET_KEY"],
        algorithm="HS256",
    )
    return client.get(f"/api/media/{file_id}?ticket={stale}").status_code == 403


if __name__ == "__main__":
    raise SystemExit(main())
