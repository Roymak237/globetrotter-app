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
import time
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
# Registry locks are held only for snapshots/mutations, never socket I/O.
# Each call has its own lock to serialize selection, delivery and teardown.
_CALLS_LOCK = threading.Lock()
_INVITATION_TTL = 60.0

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


def _send_socket(username: str, ws, payload: dict) -> bool:
    """Send to an exact registered device, never fan out selected signalling."""
    with _CONNECTIONS_LOCK:
        if ws not in _CONNECTIONS.get(username, ()):
            return False
    try:
        ws.send(json.dumps(payload))
        return True
    except Exception:
        # The current call handles failed delivery; socket finalization cleans
        # up any other calls. Never acquire another call lock while sending.
        _unregister(username, ws)
        return False


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
    try:
        valid_session = int(user.get("session_version", 0) or 0) == int(payload.get("sv", 0))
    except (TypeError, ValueError):
        return None
    if not valid_session:
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


def _begin_call(caller: str, message: dict, ws) -> dict | None:
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

    targets = sorted(set(members) - {caller})
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

    ring = {
        "type": "ring",
        "call_id": call_id,
        "room_id": room_id,
        "video": video,
        "from": caller,
        "from_display_name": _display_name(caller),
        "from_avatar_url": _avatar_for(caller),
    }

    state = {
        "record": call,
        "lock": threading.Lock(),
        "caller_ws": ws,
        "selected": None,  # (username, socket), set exactly once
        "invited": {},  # socket -> username; only successful ring deliveries
        "pending": {},
        "expires_at": time.monotonic() + _INVITATION_TTL,
        "timer": None,
        "ended": False,
    }
    with state["lock"]:
        save_call(call)
        with _CALLS_LOCK:
            _ACTIVE_CALLS[call_id] = state
        try:
            for target in targets:
                if not _may_call(caller, target):
                    continue
                with _CONNECTIONS_LOCK:
                    sockets = list(_CONNECTIONS.get(target, ()))
                for target_ws in sockets:
                    if _send_socket(target, target_ws, ring):
                        state["invited"][target_ws] = target
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
            state["pending"] = dict(state["invited"])
            reached = len(state["pending"])
            # Send under the call lock: even an immediate accept must not reach
            # the caller before it has received its call_id in this frame.
            delivered = _send_socket(caller, ws, {
                "type": "ringing", "call_id": call_id, "room_id": room_id,
                "video": video, "reached": reached,
            })
            if not delivered or not reached:
                _finish_call_locked(state, caller, "disconnect" if not delivered else "unavailable", ws)
            else:
                timer = threading.Timer(
                    max(0, state["expires_at"] - time.monotonic()),
                    _expire_call, args=(call_id,),
                )
                timer.daemon = True
                state["timer"] = timer
                timer.start()
        except Exception:
            _finish_call_locked(state, caller, "error")
            raise
    return None


def _finish_call_locked(state: dict, username: str, reason: str, exclude_ws=None) -> None:
    """Internal teardown only; caller must hold the state lock and authorize."""
    if state["ended"]:
        return
    state["ended"] = True
    record = state["record"]
    call_id = record["id"]
    with _CALLS_LOCK:
        _ACTIVE_CALLS.pop(call_id, None)
    if state["timer"] is not None:
        state["timer"].cancel()
    recipients = dict(state["pending"])
    recipients[state["caller_ws"]] = record["caller"]
    if state["selected"] is not None:
        selected_user, selected_ws = state["selected"]
        recipients[selected_ws] = selected_user
    state["pending"].clear()
    answered = bool(record.get("answered_at"))
    changes = {
        "ended_at": _now(),
        "status": "completed" if answered else (
            "declined" if reason == "decline" else "missed"
        ),
    }
    record.update(changes)
    try:
        update_call(call_id, changes)
    finally:
        for peer_ws, participant in recipients.items():
            if peer_ws is not exclude_ws:
                _send_socket(participant, peer_ws, {
                    "type": "hangup", "call_id": call_id,
                    "by": username, "reason": reason,
                })


def _expire_call(call_id: str) -> None:
    """Expire unanswered invitations even when no more client frames arrive."""
    with _CALLS_LOCK:
        state = _ACTIVE_CALLS.get(call_id)
    if state is not None:
        with state["lock"]:
            if (not state["ended"] and state["selected"] is None
                    and time.monotonic() >= state["expires_at"]):
                _finish_call_locked(state, state["record"]["caller"], "timeout")


def _disconnect(username: str, ws) -> None:
    """A lost owner ends its call; a lost invitee removes only that invitation."""
    _unregister(username, ws)
    with _CALLS_LOCK:
        states = list(_ACTIVE_CALLS.values())
    for state in states:
        with state["lock"]:
            if state["ended"]:
                continue
            if ((username == state["record"]["caller"] and ws is state["caller_ws"])
                    or state["selected"] == (username, ws)):
                _finish_call_locked(state, username, "disconnect", ws)
            elif state["pending"].get(ws) == username:
                state["pending"].pop(ws)
                if not state["pending"]:
                    _finish_call_locked(state, username, "disconnect", ws)


def _eligible_peer(state: dict, username: str) -> bool:
    """Recheck membership and blocking, including changes since the ring."""
    caller = state["record"]["caller"]
    room = get_room_by_id(state["record"]["room_id"])
    return bool(room and room.get("type") != "community"
                and caller in (room.get("members") or [])
                and username in (room.get("members") or [])
                and _may_call(caller, username))


def _handle(username: str, message: dict, ws) -> dict | None:
    """Process one inbound signalling frame and return an optional reply."""
    kind = str(message.get("type", "") or "")

    if kind == "ping":
        return {"type": "pong"}

    with _CONNECTIONS_LOCK:
        if ws not in _CONNECTIONS.get(username, ()):
            return {"type": "error", "error": "socket is not registered"}
    if kind == "call":
        return _begin_call(username, message, ws)
    if kind not in _RELAY_TYPES | {"accept", "decline", "hangup"}:
        return {"type": "error", "error": f"unsupported message type: {kind or 'missing'}"}

    call_id = str(message.get("call_id", "") or "")
    with _CALLS_LOCK:
        state = _ACTIVE_CALLS.get(call_id)
    if state is None:
        return {"type": "error", "error": "that call has ended"}

    with state["lock"]:
        if (not state["ended"] and state["selected"] is None
                and time.monotonic() >= state["expires_at"]):
            _finish_call_locked(state, state["record"]["caller"], "timeout")
        if state["ended"]:
            return {"type": "error", "error": "that call has ended"}
        caller = state["record"]["caller"]
        is_caller = username == caller and ws is state["caller_ws"]
        is_selected = state["selected"] == (username, ws)
        is_invited = state["pending"].get(ws) == username
        elsewhere = {"type": "hangup", "call_id": call_id, "reason": "answered_elsewhere"}

        if kind in _RELAY_TYPES:
            if state["selected"] is None or not (is_caller or is_selected):
                return {"type": "error", "error": "not a selected call socket"}
            selected_user, selected_ws = state["selected"]
            peer_user, peer_ws = (selected_user, selected_ws) if is_caller else (caller, state["caller_ws"])
            if message.get("to") != peer_user or not _eligible_peer(state, selected_user):
                return {"type": "error", "error": "that person is not in this call"}
            if not _send_socket(peer_user, peer_ws, {**message, "from": username}):
                _finish_call_locked(state, peer_user, "disconnect", peer_ws)
            return None

        if kind == "accept":
            if is_selected:
                return None  # Retransmission must not create a second offer.
            if state["selected"] is not None and state["invited"].get(ws) == username:
                return elsewhere
            if not is_invited or username == caller:
                return {"type": "error", "error": "not an invited call socket"}
            if not _eligible_peer(state, username):
                state["pending"].pop(ws)
                if not state["pending"]:
                    _finish_call_locked(state, username, "unavailable", ws)
                return {"type": "hangup", "call_id": call_id, "reason": "unavailable"}
            state["selected"] = (username, ws)
            losers = dict(state["pending"])
            losers.pop(ws)
            state["pending"].clear()
            if state["timer"] is not None:
                state["timer"].cancel()
            changes = {"answered_at": _now(), "status": "active"}
            state["record"].update(changes)
            update_call(call_id, changes)
            for loser_ws, loser in losers.items():
                _send_socket(loser, loser_ws, elsewhere)
            if not _send_socket(caller, state["caller_ws"], {
                "type": "accepted", "call_id": call_id, "by": username,
            }):
                _finish_call_locked(state, caller, "disconnect", state["caller_ws"])
            return None

        if is_caller or is_selected:
            _finish_call_locked(state, username, kind, ws)
        elif state["selected"] is not None and state["invited"].get(ws) == username:
            return elsewhere
        elif is_invited:
            # A busy device (including a sibling tab) cannot decline on behalf
            # of every other invitee. Only the last invitation ends the call.
            state["pending"].pop(ws)
            if not state["pending"]:
                _finish_call_locked(state, username, kind, ws)
        else:
            return {"type": "error", "error": "not a call socket"}
        return None


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

        try:
            ws.send(json.dumps({"type": "ready", "username": username}))
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

                reply = _handle(username, message, ws)
                if reply is not None:
                    ws.send(json.dumps(reply))
        except Exception:
            # A dropped connection is ordinary, not exceptional. The cleanup
            # below runs either way, so it needs no special handling.
            pass
        finally:
            _disconnect(username, ws)


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
