"""
scripts/probe_call_signalling.py

Drives the real signalling socket against a real backend to establish what a
caller is actually told when the person they are ringing is not connected.

This exists because "calls are not going through" is a symptom with several
plausible causes, and the difference between them is not visible in the source.
Run it rather than reason about it.
"""
import json
import os
import sys
import tempfile
import threading
import time

import websocket

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

os.environ["DATA_DIR"] = tempfile.mkdtemp(prefix="gt_call_probe_")
os.environ["SECRET_KEY"] = "probe-secret"

PORT = 5098
BASE = f"http://127.0.0.1:{PORT}"


def serve():
    # Werkzeug's threaded dev server, not gevent. flask-sock speaks websocket
    # over it via simple-websocket, which is enough to observe signalling
    # behaviour; production uses a gevent worker for concurrency, not for
    # different semantics.
    try:
        from app import create_app

        app = create_app()
        app.run(
            host="127.0.0.1",
            port=PORT,
            debug=False,
            use_reloader=False,
            threaded=True,
        )
    except Exception as exc:  # surfaced rather than dying silently in a thread
        print(f"SERVER FAILED TO START: {type(exc).__name__}: {exc}")
        raise


def main():
    threading.Thread(target=serve, daemon=True).start()
    time.sleep(2.5)

    import requests

    def register(username):
        requests.post(
            f"{BASE}/api/auth/register",
            json={
                "username": username,
                "password": "Passw0rd!x",
                "display_name": username.title(),
            },
            timeout=10,
        )
        r = requests.post(
            f"{BASE}/api/auth/login",
            json={"username": username, "password": "Passw0rd!x"},
            timeout=10,
        )
        return r.json()["token"]

    alice = register("alice")
    bob = register("bob")
    print(f"registered two users        alice={bool(alice)} bob={bool(bob)}")

    room = requests.post(
        f"{BASE}/api/chat/direct",
        json={"username": "bob"},
        headers={"Authorization": f"Bearer {alice}"},
        timeout=10,
    ).json()
    room_id = room.get("id") or room.get("room", {}).get("id")
    print(f"direct room                 {room_id}")

    # --- Case 1: Bob is NOT connected -------------------------------------
    ws = websocket.create_connection(
        f"ws://127.0.0.1:{PORT}/api/chat/ws?token={alice}", timeout=10
    )
    print(f"alice socket ready          {ws.recv()}")

    ws.send(json.dumps({"type": "call", "room_id": room_id, "video": False}))
    reply = json.loads(ws.recv())
    print()
    print("=== CALLEE OFFLINE ===")
    print(f"server replies              {reply}")
    print(f"reached                     {reply.get('reached')}")

    ws.settimeout(6)
    try:
        extra = ws.recv()
        print(f"anything else?              {extra}")
    except Exception:
        print("anything else?              nothing for 6s - caller rings forever")

    # --- Case 2: Bob IS connected ----------------------------------------
    bob_ws = websocket.create_connection(
        f"ws://127.0.0.1:{PORT}/api/chat/ws?token={bob}", timeout=10
    )
    bob_ws.recv()

    ws.send(json.dumps({"type": "hangup", "call_id": reply.get("call_id")}))
    time.sleep(0.4)
    ws.send(json.dumps({"type": "call", "room_id": room_id, "video": False}))
    reply2 = json.loads(ws.recv())
    print()
    print("=== CALLEE ONLINE ===")
    print(f"server replies              {reply2}")
    print(f"reached                     {reply2.get('reached')}")
    bob_ws.settimeout(5)
    print(f"bob receives                {bob_ws.recv()}")

    # --- Case 3: what presence says --------------------------------------
    pres = requests.get(
        f"{BASE}/api/chat/presence",
        params={"room_id": room_id},
        headers={"Authorization": f"Bearer {alice}"},
        timeout=10,
    )
    print()
    print(f"presence endpoint           {pres.status_code} {pres.text.strip()}")

    # The room list carries the same fact, so the conversation list can show a
    # badge without one request per room.
    rooms_online = requests.get(
        f"{BASE}/api/chat/rooms",
        headers={"Authorization": f"Bearer {alice}"},
        timeout=10,
    ).json()
    for r in rooms_online:
        print(
            f"room online flag            {r.get('type'):<10} "
            f"{r.get('name'):<16} online={r.get('online')}"
        )

    bob_ws.close()
    time.sleep(0.6)
    rooms_after = requests.get(
        f"{BASE}/api/chat/rooms",
        headers={"Authorization": f"Bearer {alice}"},
        timeout=10,
    ).json()
    for r in rooms_after:
        if r.get("type") == "direct":
            print(f"after bob disconnects       online={r.get('online')}")

    ice = requests.get(
        f"{BASE}/api/chat/calls/ice",
        headers={"Authorization": f"Bearer {alice}"},
        timeout=10,
    ).json()
    print(f"ice has_turn                {ice.get('has_turn')}")
    print(f"ice servers                 {len(ice.get('ice_servers', []))} (stun only)")


if __name__ == "__main__":
    main()
