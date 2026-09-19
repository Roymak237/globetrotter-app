"""
app/calls.py

Voice and video calling for Trip Chat.

Only the *signalling* passes through this server. Once two browsers have traded
an SDP offer/answer and a handful of ICE candidates, the audio and video flow
directly between them; none of it is relayed here. That is what makes calling
affordable on a small VPS.

The socket carries three kinds of traffic:

* ``call`` / ``accept`` / ``decline`` / ``hangup`` — call lifecycle
* ``offer`` / ``answer`` / ``ice`` — opaque WebRTC payloads, forwarded verbatim
* ``ping`` — keeps intermediaries from closing an idle socket

Payload bodies are never inspected. The server decides *who may talk to whom*
and forwards the rest untouched, which keeps this file independent of whatever
codec negotiation the browsers settle on.

A deployment note: the connection registry below is process-local, so the app
must run as one worker with many greenlets rather than several OS workers. That
is set in the Dockerfile's gunicorn invocation, and adding a second worker
would break calling by splitting the registry in two.

Routes
------
WS   /api/chat/ws          Signalling socket
GET  /api/chat/calls       Recent call history
GET  /api/chat/calls/ice   ICE server configuration for the client
GET  /api/chat/presence    Who in a room is reachable right now
"""
import datetime
import json
import os
import threading
import uuid

import jwt
from flask import Blueprint, current_app, jsonify, request

from app.auth import decode_token, get_current_user
from app.models import (
    get_calls_for_user,
    get_room_by_id,
    get_user_by_username,
    save_call,
    save_notification,
    update_call,
)

calls_bp = Blueprint("calls", __name__)

# username -> set of open sockets. One user may hold several: a phone and a
# laptop both signed in, or simply two browser tabs.
_CONNECTIONS: dict[str, set] = {}
_CONNECTIONS_LOCK = threading.Lock()

# call_id -> live call state, discarded when the call ends.
_ACTIVE_CALLS: dict[str, dict] = {}
_CALLS_LOCK = threading.Lock()

# Signal types forwarded to the peer without inspection.
_RELAY_TYPES = {"offer", "answer", "ice", "renegotiate"}


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _register(username: str, ws) -> None:
    with _CONNECTIONS_LOCK:
        _CONNECTIONS.setdefault(username, set()).add(ws)


def _unregister(username: str, ws) -> None:
    with _CONNECTIONS_LOCK:
        sockets = _CONNECTIONS.get(username)
        if not sockets:
            return
        sockets.discard(ws)
        if not sockets:
            _CONNECTIONS.pop(username, None)


def is_online(username: str) -> bool:
    with _CONNECTIONS_LOCK:
        return bool(_CONNECTIONS.get(username))


def _send_to(username: str, payload: dict) -> int:
    """Deliver *payload* to every socket held by *username*.

    Returns how many sockets accepted it. A send can fail when a browser has
    gone away without closing cleanly, so dead sockets are reaped here rather
    than accumulating.
    """
    with _CONNECTIONS_LOCK:
        sockets = list(_CONNECTIONS.get(username, ()))

    body = json.dumps(payload)
    delivered = 0
    for ws in sockets:
        try:
            ws.send(body)
            delivered += 1
        except Exception:
            _unregister(username, ws)
    return delivered


def _authenticate(token: str) -> str | None:
    """Resolve a websocket token to a username.

    The browser WebSocket API cannot set an Authorization header, so the token
    arrives as a query parameter instead. It is the same signed JWT used for
    REST calls and is verified identically, session version included.
    """
    if not token:
        return None
    try:
        payload = decode_token(token, current_app.config["SECRET_KEY"])
    except (jwt.PyJWTError, TypeError, ValueError):
        return None
    username = payload.get("sub")
    if not isinstance(username, str):
        return None
    user = get_user_by_username(username)
    if user is None:
        return None
    if int(user.get("session_version", 0) or 0) != int(payload.get("sv", 0)):
        return None
    return username


def _may_call(caller: str, callee: str) -> bool:
    """Calling is allowed unless either party has blocked the other."""
    a = set((get_user_by_username(caller) or {}).get("blocked", []) or [])
    b = set((get_user_by_username(callee) or {}).get("blocked", []) or [])
    return callee not in a and caller not in b


def _display_name(username: str) -> str:
    user = get_user_by_username(username) or {}
    return user.get("display_name") or username


def _avatar_for(username: str) -> str:
    user = get_user_by_username(username) or {}
    return user.get("avatar_url", "") or ""


def _begin_call(caller: str, message: dict) -> dict:
    """Ring everyone else in a room and record the attempt."""
    room_id = str(message.get("room_id", "") or "")
    room = get_room_by_id(room_id)
    if room is None:
        return {"type": "error", "error": "room not found"}

    # Calling the community room would ring every registered user, which is
    # never what anyone wants.
    if room.get("type") == "community":
        return {"type": "error", "error": "the community room does not support calls"}

    members = room.get("members", []) or []
    if caller not in members:
        return {"type": "error", "error": "you are not a member of this room"}

    targets = [m for m in members if m != caller]
    if not targets:
        return {"type": "error", "error": "there is nobody to call"}

    video = bool(message.get("video"))
    call_id = str(uuid.uuid4())
    call = {
        "id": call_id,
        "room_id": room_id,
        "caller": caller,
        "participants": sorted(set(members)),
        "video": video,
        "started_at": _now(),
        "answered_at": None,
        "ended_at": None,
        "status": "ringing",
    }

    with _CALLS_LOCK:
        _ACTIVE_CALLS[call_id] = {"accepted_by": set(), "record": call}
    save_call(call)

    ring = {
        "type": "ring",
        "call_id": call_id,
        "room_id": room_id,
        "video": video,
        "from": caller,
        "from_display_name": _display_name(caller),
        "from_avatar_url": _avatar_for(caller),
    }

    reached = 0
    for target in targets:
        if not _may_call(caller, target):
            continue
        reached += _send_to(target, ring)
        # A missed call should still be discoverable later, so it is also
        # recorded as a notification.
        save_notification({
            "id": str(uuid.uuid4()),
            "username": target,
            "type": "call",
            "actor": caller,
            "room_id": room_id,
            "text": f"{_display_name(caller)} called you",
            "created_at": _now(),
            "read": False,
        })

    return {
        "type": "ringing",
        "call_id": call_id,
        "room_id": room_id,
        "video": video,
        "reached": reached,
    }


def _end_call(call_id: str, username: str, reason: str) -> None:
    """Tear down a call and tell everyone still connected."""
    with _CALLS_LOCK:
        state = _ACTIVE_CALLS.pop(call_id, None)
    if state is None:
        return

    record = state["record"]
    answered = bool(record.get("answered_at"))
    update_call(call_id, {
        "ended_at": _now(),
        "status": "completed" if answered else (
            "declined" if reason == "decline" else "missed"
        ),
    })

    for participant in record.get("participants", []):
        if participant == username:
            continue
        _send_to(participant, {
            "type": "hangup",
            "call_id": call_id,
            "by": username,
            "reason": reason,
        })


def _handle(username: str, message: dict) -> dict | None:
    """Process one inbound signalling frame and return an optional reply."""
    kind = str(message.get("type", "") or "")

    if kind == "ping":
        return {"type": "pong"}

    if kind == "call":
        return _begin_call(username, message)

    if kind in _RELAY_TYPES:
        target = str(message.get("to", "") or "")
        call_id = str(message.get("call_id", "") or "")
        if not target or not call_id:
            return {"type": "error", "error": "to and call_id are required"}

        with _CALLS_LOCK:
            state = _ACTIVE_CALLS.get(call_id)
        # Only a participant may inject signalling into a call, which stops a
        # third party from hijacking a negotiation by guessing a call id.
        if state is None or username not in state["record"].get("participants", []):
            return {"type": "error", "error": "unknown call"}
        if target not in state["record"].get("participants", []):
            return {"type": "error", "error": "that person is not in this call"}

        _send_to(target, {**message, "from": username})
        return None

    if kind == "accept":
        call_id = str(message.get("call_id", "") or "")
        with _CALLS_LOCK:
            state = _ACTIVE_CALLS.get(call_id)
            if state is None:
                return {"type": "error", "error": "that call has ended"}
            if username not in state["record"].get("participants", []):
                return {"type": "error", "error": "unknown call"}
            state["accepted_by"].add(username)
            first_answer = state["record"].get("answered_at") is None
            if first_answer:
                state["record"]["answered_at"] = _now()
                state["record"]["status"] = "active"
            participants = list(state["record"].get("participants", []))

        if first_answer:
            update_call(call_id, {"answered_at": _now(), "status": "active"})

        for participant in participants:
            if participant != username:
                _send_to(participant, {
                    "type": "accepted",
                    "call_id": call_id,
                    "by": username,
                })
        return None

    if kind in ("decline", "hangup"):
        _end_call(str(message.get("call_id", "") or ""), username, kind)
        return None

    return {"type": "error", "error": f"unsupported message type: {kind or 'missing'}"}


def register_socket(sock) -> None:
    """Attach the signalling endpoint to a ``flask_sock.Sock`` instance.

    Registration happens from the app factory rather than at import time, so
    this module stays importable when websocket support is unavailable and the
    REST API keeps working instead of failing to boot.
    """

    @sock.route("/api/chat/ws")
    def signalling(ws):  # pragma: no cover - exercised over a live socket
        username = _authenticate(request.args.get("token", ""))
        if username is None:
            ws.send(json.dumps({"type": "error", "error": "authentication failed"}))
            return

        _register(username, ws)
        ws.send(json.dumps({"type": "ready", "username": username}))

        try:
            while True:
                raw = ws.receive()
                if raw is None:
                    break
                try:
                    message = json.loads(raw)
                except (TypeError, ValueError):
                    ws.send(json.dumps({"type": "error", "error": "malformed message"}))
                    continue
                if not isinstance(message, dict):
                    continue

                reply = _handle(username, message)
                if reply is not None:
                    ws.send(json.dumps(reply))
        except Exception:
            # A dropped connection is ordinary, not exceptional. The cleanup
            # below runs either way, so it needs no special handling.
            pass
        finally:
            _unregister(username, ws)
            # End any call this user was in once their last socket has gone, so
            # a closed laptop lid does not leave a call ringing forever.
            if not is_online(username):
                with _CALLS_LOCK:
                    stale = [
                        call_id for call_id, state in _ACTIVE_CALLS.items()
                        if username in state["record"].get("participants", [])
                    ]
                for call_id in stale:
                    _end_call(call_id, username, "disconnect")


@calls_bp.route("/api/chat/calls", methods=["GET"])
def call_history():
    """Recent calls involving the viewer, newest first."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    history = sorted(
        get_calls_for_user(username),
        key=lambda c: c.get("started_at", ""),
        reverse=True,
    )[:100]

    return jsonify([
        {
            "id": call.get("id"),
            "room_id": call.get("room_id"),
            "caller": call.get("caller"),
            "caller_display_name": _display_name(call.get("caller", "")),
            "video": bool(call.get("video")),
            "status": call.get("status"),
            "started_at": call.get("started_at"),
            "answered_at": call.get("answered_at"),
            "ended_at": call.get("ended_at"),
            "outgoing": call.get("caller") == username,
        }
        for call in history
    ]), 200


@calls_bp.route("/api/chat/calls/ice", methods=["GET"])
def ice_servers():
    """ICE servers for the client's RTCPeerConnection.

    STUN alone is enough for most connections. Symmetric NAT and some mobile
    carriers need a TURN relay, so credentials are read from the environment
    when one is configured; without it calling still works for the majority
    rather than failing closed for everyone.
    """
    if get_current_user(request) is None:
        return jsonify({"error": "authentication required"}), 401

    servers = [
        {"urls": "stun:stun.l.google.com:19302"},
        {"urls": "stun:stun1.l.google.com:19302"},
    ]

    turn_url = os.environ.get("TURN_URL", "").strip()
    if turn_url:
        servers.append({
            "urls": turn_url,
            "username": os.environ.get("TURN_USERNAME", ""),
            "credential": os.environ.get("TURN_PASSWORD", ""),
        })

    return jsonify({"ice_servers": servers, "has_turn": bool(turn_url)}), 200


@calls_bp.route("/api/chat/presence", methods=["GET"])
def presence():
    """Which members of a room are reachable right now.

    Scoped to a room the viewer belongs to. A global "who is online" list would
    leak the activity of people the viewer has no relationship with.
    """
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room = get_room_by_id(str(request.args.get("room_id", "") or ""))
    if room is None:
        return jsonify({"error": "room not found"}), 404

    members = room.get("members", []) or []
    if room.get("type") == "community" or username not in members:
        return jsonify({"error": "you are not a member of this room"}), 403

    online = [
        member for member in members
        if member != username and is_online(member) and _may_call(username, member)
    ]
    return jsonify({"online": sorted(online)}), 200
