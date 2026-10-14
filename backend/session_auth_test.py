"""Checks for account creation and session lifetime.

Two things were wrong and neither was visible from the server alone:

  * ``POST /api/auth/register`` created the account and returned nothing
    usable, so the app had no choice but to send a brand new arrival to the
    sign-in screen to retype the credentials they had typed a moment before.

  * Tokens expired after 24 hours. On the installed Android build that meant
    signing in again every day, which for most people is the point at which
    an app stops being worth keeping.

Revoking still has to work, though. A longer-lived token is only safe
because ``session_version`` can invalidate every outstanding token for an
account at once, so that is checked here too rather than assumed.

Run:  python backend/session_auth_test.py
"""

from __future__ import annotations

import datetime
import os
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


def run() -> int:
    tmp = tempfile.mkdtemp(prefix="kamergo-session-test-")
    # models.py reads DATA_DIR. The wrong name here does not fail loudly, it
    # writes test accounts into the real data directory.
    os.environ["DATA_DIR"] = tmp

    import jwt
    from app.main import create_app

    app = create_app()
    app.config["SECRET_KEY"] = "test-secret-for-session-checks"
    client = app.test_client()
    secret = app.config["SECRET_KEY"]

    print("\ncreating an account")
    reg = client.post(
        "/api/auth/register",
        json={"username": "newcomer", "password": "Str0ng!Passw0rd"},
    )
    body = reg.get_json() or {}
    check("register succeeds", reg.status_code == 201, f"got {reg.status_code}")
    check("register returns a token", bool(body.get("token")))
    check(
        "register returns the new profile",
        isinstance(body.get("user"), dict)
        and body["user"].get("username") == "newcomer",
    )
    check(
        "register still reports the username for older clients",
        body.get("username") == "newcomer",
    )
    check(
        "register never leaks the password hash",
        "password_hash" not in str(body),
    )

    token = body.get("token")
    if not token:
        print("\nno token issued; the rest cannot run")
        return 1

    print("\nthe token works immediately")
    auth = {"Authorization": f"Bearer {token}"}
    me = client.get("/api/auth/me", headers=auth)
    check("the registration token is accepted", me.status_code == 200,
          f"got {me.status_code}")
    check(
        "it identifies the right account",
        (me.get_json() or {}).get("username") == "newcomer",
    )

    print("\nthe session outlives a day")
    payload = jwt.decode(token, secret, algorithms=["HS256"])
    issued = datetime.datetime.fromtimestamp(payload["iat"], datetime.timezone.utc)
    expires = datetime.datetime.fromtimestamp(payload["exp"], datetime.timezone.utc)
    lifetime_hours = (expires - issued).total_seconds() / 3600
    check(
        "a session lasts well beyond 24 hours",
        lifetime_hours > 24 * 7,
        f"lifetime is {lifetime_hours:.0f}h, which still means frequent sign-ins",
    )

    print("\nsigning in returns the profile too")
    login = client.post(
        "/api/auth/login",
        json={"username": "newcomer", "password": "Str0ng!Passw0rd"},
    )
    login_body = login.get_json() or {}
    check("login succeeds", login.status_code == 200)
    check("login returns a token", bool(login_body.get("token")))
    check(
        "login returns the profile",
        isinstance(login_body.get("user"), dict)
        and login_body["user"].get("username") == "newcomer",
    )

    print("\na long session can still be revoked")
    # This is the whole reason a long lifetime is defensible. If this fails,
    # the longer expiry above is a liability rather than a convenience.
    revoke = client.post("/api/auth/sessions/revoke", headers=auth)
    if revoke.status_code == 404:
        # Route name differs; find it rather than silently skipping.
        check("a revoke route exists", False, "no /api/auth/sessions/revoke")
    else:
        check("revoking succeeds", revoke.status_code == 200,
              f"got {revoke.status_code}")
        stale = client.get("/api/auth/me", headers=auth)
        check(
            "the old token stops working at once",
            stale.status_code == 401,
            f"old token still returned {stale.status_code}",
        )

    print("\nchanging the password also ends old sessions")
    fresh = (revoke.get_json() or {}).get("token") if revoke.status_code == 200 else None
    if fresh:
        fresh_auth = {"Authorization": f"Bearer {fresh}"}
        changed = client.patch(
            "/api/auth/password",
            headers=fresh_auth,
            json={
                "current_password": "Str0ng!Passw0rd",
                "new_password": "An0ther!Passw0rd",
            },
        )
        check("password change succeeds", changed.status_code == 200,
              f"got {changed.status_code}")
        if changed.status_code == 200:
            after = client.get("/api/auth/me", headers=fresh_auth)
            check(
                "the pre-change token is rejected",
                after.status_code == 401,
                f"it still returned {after.status_code}",
            )

    print("\nrejected input is still rejected")
    dup = client.post(
        "/api/auth/register",
        json={"username": "newcomer", "password": "Str0ng!Passw0rd"},
    )
    check("a duplicate username is refused", dup.status_code == 409)
    check("the refusal carries no token", "token" not in (dup.get_json() or {}))

    weak = client.post(
        "/api/auth/register",
        json={"username": "someone_new", "password": "short"},
    )
    check("a weak password is refused", weak.status_code == 400)
    check("the refusal carries no token", "token" not in (weak.get_json() or {}))

    print(f"\n{PASSED}/{PASSED + FAILED} checks passed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(run())
