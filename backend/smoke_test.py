"""
smoke_test.py

End-to-end checks for the HTTP API, run against a real server on a real
socket rather than Flask's in-process test client.

That distinction has already earned its keep: a byte-order-mark bug once
passed every in-process test and still returned 500s in production, because
the test client never exercised the encoding path that a real request does.

The server is pointed at a throwaway data directory, so running this cannot
touch real accounts, trips or uploads.

Usage
-----
    python smoke_test.py                  # starts its own server
    python smoke_test.py http://host:port # tests an already-running server

Exit code is 0 when every check passes and 1 otherwise, so CI can gate on it.
"""
import io
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

PASSED = []
FAILED = []


# ---------------------------------------------------------------------------
# Tiny HTTP helper
# ---------------------------------------------------------------------------

def call(method, url, token=None, body=None, raw=None, content_type=None):
    """Perform one request and return (status, parsed_body).

    Errors are captured rather than raised, because a 4xx is frequently the
    expected result and the caller needs to assert on it.
    """
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token

    data = None
    if raw is not None:
        data = raw
        if content_type:
            headers["Content-Type"] = content_type
    elif body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read()
            status = response.getcode()
    except urllib.error.HTTPError as exc:
        payload = exc.read()
        status = exc.code
    except (urllib.error.URLError, OSError) as exc:
        return 0, {"error": str(exc)}

    try:
        return status, json.loads(payload.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return status, payload


def check(name, condition, detail=""):
    if condition:
        PASSED.append(name)
        print("  PASS  " + name)
    else:
        FAILED.append(name + (" :: " + str(detail) if detail else ""))
        print("  FAIL  " + name + ("  -> " + str(detail) if detail else ""))


def multipart(field_name, filename, content, mime):
    """Build a multipart/form-data body without pulling in a dependency."""
    boundary = "----kamergo" + uuid.uuid4().hex
    buf = io.BytesIO()
    buf.write(("--" + boundary + "\r\n").encode())
    buf.write((
        'Content-Disposition: form-data; name="' + field_name +
        '"; filename="' + filename + '"\r\n'
    ).encode())
    buf.write(("Content-Type: " + mime + "\r\n\r\n").encode())
    buf.write(content)
    buf.write(("\r\n--" + boundary + "--\r\n").encode())
    return buf.getvalue(), "multipart/form-data; boundary=" + boundary


# ---------------------------------------------------------------------------
# Server lifecycle
# ---------------------------------------------------------------------------

def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def seed_data_dir(target):
    """Copy the reference catalogue in and create the empty ledgers."""
    os.makedirs(os.path.join(target, "media"), exist_ok=True)
    source = os.path.join(BASE_DIR, "data", "destinations.json")
    if os.path.exists(source):
        shutil.copy(source, os.path.join(target, "destinations.json"))
    for name in (
        "users.json", "itineraries.json", "shares.json", "comments.json",
        "reviews.json", "notifications.json", "submissions.json",
        "chat_rooms.json", "chat_messages.json", "ratings.json",
        "password_resets.json", "calls.json",
    ):
        path = os.path.join(target, name)
        if not os.path.exists(path):
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("[]")


def start_server(port, data_dir):
    env = dict(os.environ)
    env["DATA_DIR"] = data_dir
    env["SECRET_KEY"] = "smoke-test-secret"
    env["PYTHONPATH"] = BASE_DIR

    # The server's log goes to a file rather than a pipe. A pipe nobody drains
    # fills after a few dozen access-log lines, at which point the server
    # blocks forever on its own write and every later request times out.
    log_path = os.path.join(data_dir, "server.log")
    log = open(log_path, "wb")
    process = subprocess.Popen(
        [sys.executable, "-c",
         "from app import create_app; create_app().run("
         "host='127.0.0.1', port=" + str(port) + ", threaded=True)"],
        cwd=BASE_DIR, env=env,
        stdout=log, stderr=subprocess.STDOUT,
    )

    base = "http://127.0.0.1:" + str(port)
    for _ in range(80):
        if process.poll() is not None:
            log.close()
            with open(log_path, "r", encoding="utf-8", errors="replace") as fh:
                print(fh.read())
            raise SystemExit("server exited before it became ready")
        status, _body = call("GET", base + "/healthz")
        if status == 200:
            return process, base
        time.sleep(0.25)
    raise SystemExit("server did not become ready in time")


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

def register(base, username):
    """Create an account and return a bearer token for it.

    Registration deliberately does not hand back a token — it confirms the
    account and leaves the caller to sign in — so the login step here mirrors
    exactly what the app does after a successful sign-up.
    """
    status, body = call("POST", base + "/api/auth/register", body={
        "username": username,
        "password": "TestPass123!",
    })
    if status not in (200, 201):
        raise SystemExit("could not register " + username + ": " + str(body))

    status, body = call("POST", base + "/api/auth/login", body={
        "username": username,
        "password": "TestPass123!",
    })
    if status != 200 or not isinstance(body, dict) or "token" not in body:
        raise SystemExit("could not sign in as " + username + ": " + str(body))
    return body["token"]


def run(base):
    suffix = uuid.uuid4().hex[:8]
    alice = "alice" + suffix
    bob = "bob" + suffix
    carol = "carol" + suffix

    print("\nauth and profile")
    a_token = register(base, alice)
    b_token = register(base, bob)
    c_token = register(base, carol)
    check("register issues a token", bool(a_token))

    status, body = call("PUT", base + "/api/me/bio", a_token, {"bio": "Loves the coast."})
    check("set bio", status == 200, body)

    status, body = call("GET", base + "/api/users/" + alice, b_token)
    check("public profile shows bio", status == 200 and body.get("bio") == "Loves the coast.", body)

    status, body = call("PUT", base + "/api/me/interests", a_token, {"interests": ["beach", "food"]})
    check("set interests", status == 200, body)

    print("\npassword reset")
    # Reset accepts a username or an email address; the username path is used
    # here because registration does not ask for an email up front.
    status, body = call("POST", base + "/api/auth/request-password-reset",
                        body={"identifier": carol})
    code = body.get("code") if isinstance(body, dict) else None
    check("reset request accepted", status == 200, body)
    status, body = call("POST", base + "/api/auth/request-password-reset",
                        body={"identifier": "nobody-here-at-all"})
    check("unknown account gives nothing away", status == 200, body)
    if code:
        status, body = call("POST", base + "/api/auth/reset-password", body={
            "identifier": carol,
            "code": code,
            "new_password": "BrandNewPass1!",
        })
        check("reset with correct code", status == 200, body)
        status, body = call("POST", base + "/api/auth/login",
                            body={"username": carol, "password": "BrandNewPass1!"})
        check("login with new password", status == 200, body)
        if status == 200:
            c_token = body["token"]
        status, body = call("POST", base + "/api/auth/reset-password", body={
            "identifier": carol,
            "code": code,
            "new_password": "AnotherPass1!",
        })
        check("code cannot be reused", status >= 400, body)

    print("\nmedia")
    png = bytes.fromhex(
        "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
        "890000000a49444154789c6360000002000100ffff03000006000557bfabd400"
        "00000049454e44ae426082"
    )
    payload, ctype = multipart("file", "pixel.png", png, "image/png")
    status, body = call("POST", base + "/api/media", a_token, raw=payload, content_type=ctype)
    media_url = body.get("url") if isinstance(body, dict) else None
    check("upload a png", status in (200, 201) and bool(media_url), body)

    if media_url:
        status, body = call("GET", base + media_url)
        check("uploaded file is served back", status == 200, status)

    payload, ctype = multipart("file", "evil.exe", b"MZ\x90\x00", "application/x-msdownload")
    status, body = call("POST", base + "/api/media", a_token, raw=payload, content_type=ctype)
    check("executable upload is refused", status >= 400, status)

    status, body = call("GET", base + "/api/media/..%2f..%2fusers.json")
    check("path traversal is refused", status >= 400, status)

    if media_url:
        status, body = call("PUT", base + "/api/me/avatar", a_token, {"avatar": media_url})
        check("set avatar", status == 200, body)

    print("\ndirect chat, attachments and blocking")
    status, body = call("POST", base + "/api/chat/direct", a_token, {"username": bob})
    dm_id = body.get("id") if isinstance(body, dict) else None
    check("open a direct conversation", status in (200, 201) and bool(dm_id), body)

    status, body = call("POST", base + "/api/chat/rooms/" + str(dm_id) + "/messages",
                        a_token, {"text": "Meet at Limbe beach on Saturday"})
    msg_id = body.get("id") if isinstance(body, dict) else None
    check("send a message", status in (200, 201) and bool(msg_id), body)

    status, body = call("POST", base + "/api/chat/rooms/" + str(dm_id) + "/messages",
                        a_token, {"text": "", "attachment": {"url": media_url, "type": "image"}})
    check("send an attachment", status in (200, 201), body)

    status, body = call("POST", base + "/api/chat/rooms/" + str(dm_id) + "/messages",
                        a_token, {"text": "x", "attachment": {"url": "https://evil.test/x.png", "type": "image"}})
    check("off-site attachment is refused", status >= 400, body)

    status, body = call("PATCH", base + "/api/chat/messages/" + str(msg_id),
                        a_token, {"text": "Meet at Limbe beach on Sunday"})
    check("edit own message", status == 200, body)

    status, body = call("PATCH", base + "/api/chat/messages/" + str(msg_id),
                        b_token, {"text": "hijacked"})
    check("cannot edit someone else's message", status >= 400, body)

    status, body = call("GET", base + "/api/chat/rooms/" + str(dm_id) + "/search?q=Limbe", a_token)
    check("search finds the message", status == 200 and len(body or []) >= 1, body)

    status, body = call("GET", base + "/api/chat/rooms/" + str(dm_id) + "/media", a_token)
    check("shared media gallery", status == 200 and len(body or []) >= 1, body)

    status, body = call("POST", base + "/api/chat/rooms/" + str(dm_id) + "/typing", a_token, {"typing": True})
    check("publish typing", status == 200, body)
    status, body = call("GET", base + "/api/chat/rooms/" + str(dm_id) + "/typing", b_token)
    # The endpoint returns display objects so the UI can show a name without a
    # second lookup; the username is the field worth asserting on.
    entries = body if isinstance(body, list) else (body or {}).get("typing") or []
    names = [
        entry.get("username") if isinstance(entry, dict) else entry
        for entry in entries
    ]
    check("peer sees typing", status == 200 and alice in names, body)

    status, body = call("POST", base + "/api/chat/rooms/" + str(dm_id) + "/mute", a_token, {"muted": True})
    check("mute a conversation", status == 200, body)

    status, body = call("POST", base + "/api/chat/messages/" + str(msg_id) + "/reactions",
                        b_token, {"emoji": "\U0001F44D"})
    check("react to a message", status in (200, 201), body)

    status, body = call("POST", base + "/api/chat/blocks", b_token, {"username": alice})
    check("block a user", status in (200, 201), body)
    status, body = call("POST", base + "/api/chat/rooms/" + str(dm_id) + "/messages",
                        a_token, {"text": "still there?"})
    check("blocked sender is refused", status >= 400, body)
    status, body = call("DELETE", base + "/api/chat/blocks/" + alice, b_token)
    check("unblock a user", status == 200, body)

    print("\ngroups")
    status, body = call("POST", base + "/api/chat/rooms", a_token,
                        {"name": "Coast Trip " + suffix, "members": [bob]})
    room_id = body.get("id") if isinstance(body, dict) else None
    invite = body.get("invite_code") if isinstance(body, dict) else None
    check("create a group", status in (200, 201) and bool(room_id), body)
    check("group has an invite code", bool(invite), body)

    status, body = call("PATCH", base + "/api/chat/groups/" + str(room_id), a_token,
                        {"name": "Coast Trip Renamed", "description": "Two days on the coast"})
    check("rename a group", status == 200, body)

    status, body = call("PATCH", base + "/api/chat/groups/" + str(room_id), b_token, {"name": "Nope"})
    check("non-admin cannot rename", status >= 400, body)

    if invite:
        status, body = call("POST", base + "/api/chat/groups/join", c_token, {"code": invite})
        check("join by invite code", status in (200, 201), body)

    status, body = call("POST", base + "/api/chat/groups/" + str(room_id) + "/admins",
                        a_token, {"username": bob})
    check("promote to admin", status == 200, body)
    status, body = call("DELETE", base + "/api/chat/groups/" + str(room_id) + "/admins/" + alice,
                        b_token)
    check("creator cannot be demoted", status >= 400, body)

    status, body = call("DELETE", base + "/api/chat/groups/" + str(room_id) + "/members/" + carol,
                        a_token)
    check("remove a member", status == 200, body)

    status, body = call("POST", base + "/api/chat/groups/" + str(room_id) + "/requests", c_token, {})
    check("request to join", status in (200, 201), body)
    status, body = call("GET", base + "/api/chat/groups/" + str(room_id) + "/requests", a_token)
    check("admin lists join requests", status == 200 and len(body or []) >= 1, body)
    status, body = call("POST", base + "/api/chat/groups/" + str(room_id) + "/requests/" + carol,
                        a_token, {"approve": True})
    check("approve a join request", status == 200, body)

    status, body = call("POST", base + "/api/chat/groups/" + str(room_id) + "/invite/rotate", a_token)
    rotated = body.get("invite_code") if isinstance(body, dict) else None
    check("rotate the invite code", status == 200 and rotated and rotated != invite, body)
    if invite:
        status, body = call("POST", base + "/api/chat/groups/join", b_token, {"code": invite})
        check("old invite code stops working", status >= 400, body)

    status, body = call("GET", base + "/api/chat/groups/discover", c_token)
    check("discover groups", status == 200, body)

    print("\nforwarding")
    status, body = call("POST", base + "/api/chat/messages/" + str(msg_id) + "/forward",
                        a_token, {"room_id": room_id})
    check("forward a message", status in (200, 201), body)

    print("\nplaces")
    status, destinations = call("GET", base + "/api/destinations")
    check("destination catalogue loads", status == 200 and len(destinations or []) > 0, status)

    dest_id = None
    if isinstance(destinations, list):
        for item in destinations:
            if item.get("latitude") and item.get("longitude"):
                dest_id = item.get("id")
                break
        if dest_id is None and destinations:
            dest_id = destinations[0].get("id")

    if dest_id:
        status, body = call("GET", base + "/api/destinations/" + str(dest_id) + "/nearby")
        check("nearby destinations", status == 200 and isinstance(body, list), body)

        status, body = call("PUT", base + "/api/destinations/" + str(dest_id) + "/rating",
                            a_token, {"stars": 5})
        check("rate a destination", status == 200 and body.get("mine") == 5, body)
        status, body = call("PUT", base + "/api/destinations/" + str(dest_id) + "/rating",
                            a_token, {"stars": 9})
        check("out-of-range rating refused", status >= 400, body)
        status, body = call("GET", base + "/api/destinations/" + str(dest_id) + "/rating", a_token)
        check("read back the rating", status == 200 and body.get("count", 0) >= 1, body)
        status, body = call("DELETE", base + "/api/destinations/" + str(dest_id) + "/rating", a_token)
        check("withdraw the rating", status == 200 and body.get("mine") is None, body)

        status, body = call("GET", base + "/api/destinations/nope-not-real/nearby")
        check("unknown destination is a 404", status == 404, status)

    print("\ncalls and presence")
    status, body = call("GET", base + "/api/chat/calls", a_token)
    check("call history", status == 200, body)
    status, body = call("GET", base + "/api/chat/calls/ice", a_token)
    check("ICE servers offered", status == 200 and len(body.get("ice_servers") or []) >= 1, body)
    # Presence is scoped to a room the viewer belongs to, so a global "who is
    # online" list cannot be harvested.
    status, body = call("GET", base + "/api/chat/presence?room_id=" + str(dm_id), a_token)
    check("presence lookup", status == 200, body)
    status, body = call("GET", base + "/api/chat/presence?room_id=" + str(room_id), c_token)
    check("presence needs membership or a real room", status in (200, 403, 404), body)

    print("\nauthentication guards")
    for method, path in (
        ("GET", "/api/chat/rooms"),
        ("GET", "/api/me/interests"),
        ("POST", "/api/media"),
        ("GET", "/api/chat/calls"),
        ("PUT", "/api/me/avatar"),
        ("GET", "/api/chat/groups/discover"),
    ):
        status, _body = call(method, base + path)
        check("unauthenticated " + method + " " + path + " is refused", status == 401, status)


def main():
    if len(sys.argv) > 1:
        run(sys.argv[1].rstrip("/"))
    else:
        data_dir = tempfile.mkdtemp(prefix="kamergo-smoke-")
        seed_data_dir(data_dir)
        process, base = start_server(free_port(), data_dir)
        try:
            run(base)
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
            shutil.rmtree(data_dir, ignore_errors=True)

    total = len(PASSED) + len(FAILED)
    print("\n" + str(len(PASSED)) + "/" + str(total) + " checks passed")
    if FAILED:
        print("\nfailures:")
        for name in FAILED:
            print("  - " + name)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
