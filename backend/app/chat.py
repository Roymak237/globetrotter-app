"""
app/chat.py

Trip Chat: a community room every traveller shares, private one-to-one
conversations, and invite-only groups.

Message delivery is poll-based with a ``since`` cursor. Call signalling is the
one thing that genuinely needs a socket, and that lives in ``app/calls.py``;
keeping ordinary messaging on polling means a dropped socket can never cost
someone their chat history.

Routes
------
GET    /api/chat/rooms                     Rooms visible to the viewer
POST   /api/chat/rooms                     Create a group
GET    /api/chat/rooms/<room_id>/messages  Messages, optionally since a cursor
POST   /api/chat/rooms/<room_id>/messages  Post a message
PATCH  /api/chat/messages/<message_id>     Edit your own message
POST   /api/chat/messages/<message_id>/forward   Forward a message elsewhere
GET    /api/chat/rooms/<room_id>/search    Search within one conversation
GET    /api/chat/rooms/<room_id>/media     Photos, videos and files shared here
POST   /api/chat/rooms/<room_id>/read      Move the viewer's read cursor
POST   /api/chat/rooms/<room_id>/typing    Announce that you are typing
GET    /api/chat/rooms/<room_id>/typing    Who else is typing right now
POST   /api/chat/rooms/<room_id>/mute      Mute or unmute a conversation
POST   /api/chat/rooms/<room_id>/members   Add someone to a group
DELETE /api/chat/rooms/<room_id>/members   Leave a group
POST   /api/chat/direct                    Open (or reuse) a direct conversation
POST   /api/chat/messages/<message_id>/reactions  Toggle an emoji reaction
DELETE /api/chat/messages/<message_id>     Delete your own message
GET    /api/chat/users/search              Find people to talk to
POST   /api/chat/blocks                    Block someone
DELETE /api/chat/blocks/<username>         Unblock someone
GET    /api/chat/blocks                    Who you have blocked
"""
import datetime
import secrets
import threading
import time
import uuid

from flask import Blueprint, jsonify, request

from app.auth import get_current_user
from app.models import (
    get_all_rooms,
    get_all_users,
    get_message_by_id,
    get_messages_for_room,
    get_room_by_id,
    get_user_by_username,
    save_message,
    save_notification,
    save_room,
    update_message,
    update_room,
    update_user,
)

chat_bp = Blueprint("chat", __name__)

COMMUNITY_ROOM_ID = "community"
MAX_MESSAGE_LENGTH = 2000
MAX_ROOM_NAME_LENGTH = 80
MESSAGE_PAGE_SIZE = 200

# How long a "user is typing" ping stays live. Long enough to survive the gap
# between keystrokes, short enough that a closed tab stops showing as typing.
TYPING_TTL_SECONDS = 6

# Typing state is deliberately in-memory: it is worthless a few seconds after it
# is written, so persisting it would mean disk writes on every keystroke.
_TYPING: dict[str, dict[str, float]] = {}
_TYPING_LOCK = threading.Lock()


def _mark_typing(room_id: str, username: str) -> None:
    with _TYPING_LOCK:
        _TYPING.setdefault(room_id, {})[username] = time.monotonic()


def _who_is_typing(room_id: str, viewer: str) -> list:
    """Live typists in a room, excluding the viewer, pruning expired entries."""
    cutoff = time.monotonic() - TYPING_TTL_SECONDS
    with _TYPING_LOCK:
        room_state = _TYPING.get(room_id, {})
        fresh = {u: t for u, t in room_state.items() if t > cutoff}
        if fresh:
            _TYPING[room_id] = fresh
        else:
            _TYPING.pop(room_id, None)
        return sorted(u for u in fresh if u != viewer)


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _new_invite_code() -> str:
    """A short code people can read off a screen and retype.

    Uses an unambiguous alphabet: no O/0 or I/1, because these get shared by
    voice and screenshot far more often than they get copied and pasted.
    """
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(8))


def _clean_attachment(raw: object) -> dict | None:
    """Validate the attachment descriptor echoed back from an upload.

    Only the URL is trusted structurally; the rest is cosmetic metadata that is
    clamped to sane lengths so a crafted payload cannot bloat the message store.
    """
    if not isinstance(raw, dict):
        return None
    url = str(raw.get("url", "") or "").strip()
    # Must point at our own media endpoint. This blocks the message store from
    # becoming a vector for embedding third-party tracking URLs.
    if not url.startswith("/api/media/"):
        return None
    kind = str(raw.get("kind", "") or "file").strip().lower()
    if kind not in ("image", "video", "audio", "file"):
        kind = "file"
    try:
        size = int(raw.get("size", 0) or 0)
    except (TypeError, ValueError):
        size = 0
    return {
        "url": url,
        "kind": kind,
        "filename": str(raw.get("filename", "") or "")[:120],
        "content_type": str(raw.get("content_type", "") or "")[:80],
        "size": max(0, size),
        "duration_ms": max(0, int(raw.get("duration_ms", 0) or 0))
        if str(raw.get("duration_ms", "")).strip().isdigit() else 0,
    }


def _ensure_community_room() -> dict:
    """The shared room is created on first use so there is no seeding step."""
    room = get_room_by_id(COMMUNITY_ROOM_ID)
    if room is None:
        room = {
            "id": COMMUNITY_ROOM_ID,
            "type": "community",
            "name": "Kamer-Go Community",
            "description": "Say hello and swap tips with other travellers.",
            "created_by": None,
            "members": [],
            "created_at": _now(),
            "read_cursors": {},
        }
        save_room(room)
    return room


def _is_member(room: dict, username: str) -> bool:
    """Community is open to every signed-in user; other rooms are explicit."""
    if room.get("type") == "community":
        return True
    return username in (room.get("members", []) or [])


def _is_admin(room: dict, username: str) -> bool:
    """Group admins, with the creator always counted so a group cannot be orphaned."""
    if room.get("type") != "group":
        return False
    if room.get("created_by") == username:
        return True
    return username in (room.get("admins", []) or [])


def _blocked_by(username: str) -> set:
    user = get_user_by_username(username) or {}
    return set(user.get("blocked", []) or [])


def _is_blocked_between(a: str, b: str) -> bool:
    """True when either party has blocked the other.

    Blocking is symmetric in effect: the blocker stops seeing the blocked user,
    and the blocked user loses the ability to reach the blocker. Checking both
    directions here keeps that from depending on which endpoint is called.
    """
    return b in _blocked_by(a) or a in _blocked_by(b)


def _display_name(username: str) -> str:
    user = get_user_by_username(username) or {}
    return user.get("display_name") or username


def _avatar_for(username: str) -> str:
    user = get_user_by_username(username) or {}
    return user.get("avatar_url", "") or ""


def _serialize_message(message: dict, viewer: str | None) -> dict:
    """Shape a message, collapsing raw reaction maps into per-emoji counts."""
    raw = message.get("reactions", {}) or {}
    reactions = [
        {
            "emoji": emoji,
            "count": len(users),
            "reacted": bool(viewer and viewer in users),
        }
        for emoji, users in sorted(raw.items())
        if users
    ]

    reply_to = None
    if message.get("reply_to"):
        parent = get_message_by_id(message["reply_to"])
        if parent is not None:
            reply_to = {
                "id": parent.get("id"),
                "username": parent.get("username"),
                "display_name": _display_name(parent.get("username", "")),
                "text": (parent.get("text", "") or "")[:140],
                "deleted": bool(parent.get("deleted")),
            }

    deleted = bool(message.get("deleted"))
    attachment = message.get("attachment") or None
    # Older rows stored only a bare URL. Promote those so the client has one
    # shape to render rather than two.
    if attachment is None and message.get("attachment_url"):
        attachment = {
            "url": message.get("attachment_url"),
            "kind": "file",
            "filename": "",
            "size": 0,
            "content_type": "",
        }

    return {
        "id": message.get("id"),
        "room_id": message.get("room_id"),
        "username": message.get("username"),
        "display_name": _display_name(message.get("username", "")),
        "avatar_url": _avatar_for(message.get("username", "")),
        "text": "" if deleted else message.get("text", ""),
        "attachment_url": None if deleted else message.get("attachment_url"),
        "attachment": None if deleted else attachment,
        "forwarded_from": None if deleted else message.get("forwarded_from"),
        "reply_to": reply_to,
        "created_at": message.get("created_at"),
        "edited_at": message.get("edited_at"),
        "deleted": deleted,
        "reactions": [] if deleted else reactions,
        "mine": bool(viewer and message.get("username") == viewer),
    }


def _serialize_room(room: dict, viewer: str) -> dict:
    """Shape a room with its last message and the viewer's unread count."""
    messages = sorted(
        get_messages_for_room(room.get("id", "")),
        key=lambda m: m.get("created_at", ""),
    )
    cursor = (room.get("read_cursors", {}) or {}).get(viewer, "")
    unread = sum(
        1 for m in messages
        if m.get("created_at", "") > cursor and m.get("username") != viewer
    )

    name = room.get("name", "")
    avatar = ""
    other_username = None
    if room.get("type") == "direct":
        # A direct conversation is labelled with whoever you are talking to.
        others = [m for m in (room.get("members", []) or []) if m != viewer]
        if others:
            other_username = others[0]
            name = _display_name(other_username)
            avatar = _avatar_for(other_username)

    members = room.get("members", []) or []
    admins = list(room.get("admins", []) or [])
    if room.get("type") == "group" and room.get("created_by"):
        # The creator is an admin implicitly, so surface that in the payload
        # rather than making every client re-derive it.
        creator = room["created_by"]
        if creator not in admins and creator in members:
            admins.append(creator)

    last = messages[-1] if messages else None
    return {
        "id": room.get("id"),
        "type": room.get("type"),
        "name": name,
        "avatar_url": avatar,
        "description": room.get("description", ""),
        "members": members,
        "member_count": len(members),
        "admins": sorted(admins),
        "is_admin": _is_admin(room, viewer),
        "other_username": other_username,
        "blocked": bool(other_username and _is_blocked_between(viewer, other_username)),
        "muted": viewer in (room.get("muted_by", []) or []),
        "invite_code": room.get("invite_code") if _is_admin(room, viewer) else None,
        "pending_requests": (
            len(room.get("join_requests", []) or []) if _is_admin(room, viewer) else 0
        ),
        "unread": unread,
        "last_message": _serialize_message(last, viewer) if last else None,
        "last_activity": last.get("created_at") if last else room.get("created_at"),
    }


@chat_bp.route("/api/chat/rooms", methods=["GET"])
def list_rooms():
    """Rooms the viewer can see, most recently active first."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    _ensure_community_room()
    visible = []
    for room in get_all_rooms():
        if not _is_member(room, username):
            continue
        if room.get("type") == "direct":
            # A blocked conversation disappears from the list rather than
            # sitting there inert; the history is kept in case of an unblock.
            others = [m for m in (room.get("members", []) or []) if m != username]
            if others and _is_blocked_between(username, others[0]):
                continue
        visible.append(room)

    rooms = [_serialize_room(room, username) for room in visible]
    rooms.sort(key=lambda r: r.get("last_activity") or "", reverse=True)
    return jsonify(rooms), 200


@chat_bp.route("/api/chat/rooms", methods=["POST"])
def create_room():
    """Create a group room with the viewer as its first member."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    name = str(data.get("name", "") or "").strip()
    if not name:
        return jsonify({"error": "name is required"}), 400
    if len(name) > MAX_ROOM_NAME_LENGTH:
        return jsonify(
            {"error": f"name must be {MAX_ROOM_NAME_LENGTH} characters or fewer"}
        ), 400

    members = {username}
    for candidate in data.get("members", []) or []:
        candidate = str(candidate or "").strip().lower()
        if candidate and get_user_by_username(candidate):
            members.add(candidate)

    room = {
        "id": str(uuid.uuid4()),
        "type": "group",
        "name": name,
        "description": str(data.get("description", "") or "").strip(),
        "avatar_url": str(data.get("avatar_url", "") or "").strip(),
        "created_by": username,
        "members": sorted(members),
        "admins": [username],
        "invite_code": _new_invite_code(),
        "join_requests": [],
        "muted_by": [],
        "created_at": _now(),
        "read_cursors": {},
    }
    save_room(room)
    return jsonify(_serialize_room(room, username)), 201


@chat_bp.route("/api/chat/direct", methods=["POST"])
def open_direct():
    """Return the conversation with another user, creating it if needed."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    other = str(data.get("username", "") or "").strip().lower()
    if not other:
        return jsonify({"error": "username is required"}), 400
    if other == username:
        return jsonify({"error": "you cannot message yourself"}), 400
    if get_user_by_username(other) is None:
        return jsonify({"error": "user not found"}), 404
    if _is_blocked_between(username, other):
        return jsonify({"error": "you cannot message this person"}), 403

    pair = sorted([username, other])
    for room in get_all_rooms():
        if room.get("type") == "direct" and sorted(room.get("members", [])) == pair:
            return jsonify(_serialize_room(room, username)), 200

    room = {
        "id": str(uuid.uuid4()),
        "type": "direct",
        "name": "",
        "description": "",
        "created_by": username,
        "members": pair,
        "created_at": _now(),
        "read_cursors": {},
    }
    save_room(room)
    return jsonify(_serialize_room(room, username)), 201


@chat_bp.route("/api/chat/rooms/<room_id>/messages", methods=["GET"])
def list_messages(room_id: str):
    """Messages oldest first. ``?since=<iso>`` returns only newer ones."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    if room_id == COMMUNITY_ROOM_ID:
        _ensure_community_room()
    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    messages = sorted(
        get_messages_for_room(room_id), key=lambda m: m.get("created_at", "")
    )

    since = str(request.args.get("since", "") or "").strip()
    if since:
        messages = [m for m in messages if m.get("created_at", "") > since]
    else:
        # Without a cursor the client is opening the room, so send the tail.
        messages = messages[-MESSAGE_PAGE_SIZE:]

    return jsonify([_serialize_message(m, username) for m in messages]), 200


@chat_bp.route("/api/chat/rooms/<room_id>/messages", methods=["POST"])
def post_message(room_id: str):
    """Post a message, optionally as a reply to another one."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    if room_id == COMMUNITY_ROOM_ID:
        _ensure_community_room()
    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    # A blocked pair keeps its history but can no longer add to it.
    if room.get("type") == "direct":
        others = [m for m in (room.get("members", []) or []) if m != username]
        if others and _is_blocked_between(username, others[0]):
            return jsonify({"error": "you cannot message this person"}), 403

    data = request.get_json(silent=True) or {}
    text = str(data.get("text", "") or "").strip()
    raw_attachment = data.get("attachment")
    attachment = _clean_attachment(raw_attachment)
    # Dropping a rejected attachment silently would show the sender a message
    # they believe carries a photo when it does not, so say so instead.
    if raw_attachment and attachment is None:
        return jsonify(
            {"error": "attachments must be uploaded to this app before sending"}
        ), 400
    attachment_url = attachment["url"] if attachment else str(
        data.get("attachment_url", "") or ""
    ).strip()
    if attachment_url and not attachment_url.startswith("/api/media/"):
        return jsonify(
            {"error": "attachments must be uploaded to this app before sending"}
        ), 400
    if not text and not attachment_url:
        return jsonify({"error": "message text is required"}), 400
    if len(text) > MAX_MESSAGE_LENGTH:
        return jsonify(
            {"error": f"message must be {MAX_MESSAGE_LENGTH} characters or fewer"}
        ), 400

    reply_to = data.get("reply_to") or None
    if reply_to:
        parent = get_message_by_id(reply_to)
        if parent is None or parent.get("room_id") != room_id:
            return jsonify({"error": "message being replied to was not found"}), 404

    message = {
        "id": str(uuid.uuid4()),
        "room_id": room_id,
        "username": username,
        "text": text,
        "attachment_url": attachment_url or None,
        "attachment": attachment,
        "forwarded_from": None,
        "reply_to": reply_to,
        "created_at": _now(),
        "edited_at": None,
        "deleted": False,
        "reactions": {},
    }
    save_message(message)

    # The sender has obviously stopped typing now that the message has landed.
    with _TYPING_LOCK:
        _TYPING.get(room_id, {}).pop(username, None)

    # Direct messages are the one place a notification is worth the noise, and
    # only when the recipient has not muted the conversation.
    if room.get("type") == "direct":
        muted = set(room.get("muted_by", []) or [])
        for member in room.get("members", []) or []:
            if member == username or member in muted:
                continue
            save_notification({
                "id": str(uuid.uuid4()),
                "username": member,
                "type": "message",
                "actor": username,
                "room_id": room_id,
                "text": f"{_display_name(username)} sent you a message",
                "created_at": _now(),
                "read": False,
            })

    return jsonify(_serialize_message(message, username)), 201


@chat_bp.route("/api/chat/rooms/<room_id>/read", methods=["POST"])
def mark_room_read(room_id: str):
    """Move the viewer's read cursor to now, clearing the unread badge."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    cursors = dict(room.get("read_cursors", {}) or {})
    cursors[username] = _now()
    update_room(room_id, {"read_cursors": cursors})
    return jsonify({"message": "room marked read"}), 200


@chat_bp.route("/api/chat/rooms/<room_id>/members", methods=["POST"])
def add_member(room_id: str):
    """Add another user to a group."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if room.get("type") != "group":
        return jsonify({"error": "only groups take members"}), 400
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    data = request.get_json(silent=True) or {}
    invitee = str(data.get("username", "") or "").strip().lower()
    if not invitee or get_user_by_username(invitee) is None:
        return jsonify({"error": "user not found"}), 404

    members = list(room.get("members", []) or [])
    if invitee not in members:
        members.append(invitee)
        room = update_room(room_id, {"members": sorted(members)}) or room
        save_notification({
            "id": str(uuid.uuid4()),
            "username": invitee,
            "type": "invite",
            "actor": username,
            "room_id": room_id,
            "text": f"{_display_name(username)} added you to {room.get('name', 'a group')}",
            "created_at": _now(),
            "read": False,
        })

    return jsonify(_serialize_room(room, username)), 200


@chat_bp.route("/api/chat/rooms/<room_id>/members", methods=["DELETE"])
def leave_room(room_id: str):
    """Leave a group."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if room.get("type") != "group":
        return jsonify({"error": "you can only leave a group"}), 400

    members = [m for m in (room.get("members", []) or []) if m != username]
    update_room(room_id, {"members": members})
    return jsonify({"message": "left the group"}), 200


@chat_bp.route("/api/chat/messages/<message_id>/reactions", methods=["POST"])
def toggle_reaction(message_id: str):
    """Add the viewer's reaction, or remove it if it is already there."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    message = get_message_by_id(message_id)
    if message is None:
        return jsonify({"error": "message not found"}), 404

    room = get_room_by_id(message.get("room_id", ""))
    if room is None or not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    data = request.get_json(silent=True) or {}
    emoji = str(data.get("emoji", "") or "").strip()
    if not emoji or len(emoji) > 8:
        return jsonify({"error": "emoji is required"}), 400

    reactions = {k: list(v) for k, v in (message.get("reactions", {}) or {}).items()}
    users = reactions.get(emoji, [])
    if username in users:
        users.remove(username)
    else:
        users.append(username)

    if users:
        reactions[emoji] = users
    else:
        reactions.pop(emoji, None)

    updated = update_message(message_id, {"reactions": reactions}) or message
    return jsonify(_serialize_message(updated, username)), 200


@chat_bp.route("/api/chat/messages/<message_id>", methods=["DELETE"])
def delete_message(message_id: str):
    """Soft-delete your own message so replies pointing at it still resolve."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    message = get_message_by_id(message_id)
    if message is None:
        return jsonify({"error": "message not found"}), 404
    if message.get("username") != username:
        return jsonify({"error": "you can only delete your own messages"}), 403

    updated = update_message(
        message_id,
        {"deleted": True, "text": "", "attachment_url": None, "reactions": {}},
    ) or message
    return jsonify(_serialize_message(updated, username)), 200


@chat_bp.route("/api/chat/users/search", methods=["GET"])
def search_users():
    """Find people by username or display name."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    query = str(request.args.get("q", "") or "").strip().lower()
    if not query:
        return jsonify([]), 200

    results = []
    for user in get_all_users():
        candidate = user.get("username", "")
        if candidate == username:
            continue
        haystack = f"{candidate} {user.get('display_name', '')}".lower()
        if query in haystack:
            results.append({
                "username": candidate,
                "display_name": user.get("display_name") or candidate,
                "avatar_url": user.get("avatar_url", "") or "",
            })
        if len(results) >= 20:
            break

    return jsonify(results), 200


@chat_bp.route("/api/chat/messages/<message_id>", methods=["PATCH"])
def edit_message(message_id: str):
    """Edit the text of your own message."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    message = get_message_by_id(message_id)
    if message is None:
        return jsonify({"error": "message not found"}), 404
    if message.get("username") != username:
        return jsonify({"error": "you can only edit your own messages"}), 403
    if message.get("deleted"):
        return jsonify({"error": "this message was deleted"}), 400

    data = request.get_json(silent=True) or {}
    text = str(data.get("text", "") or "").strip()
    # An attachment-only message may not be emptied into nothing.
    if not text and not message.get("attachment_url"):
        return jsonify({"error": "message text is required"}), 400
    if len(text) > MAX_MESSAGE_LENGTH:
        return jsonify(
            {"error": f"message must be {MAX_MESSAGE_LENGTH} characters or fewer"}
        ), 400

    updated = update_message(
        message_id, {"text": text, "edited_at": _now()}
    ) or message
    return jsonify(_serialize_message(updated, username)), 200


@chat_bp.route("/api/chat/messages/<message_id>/forward", methods=["POST"])
def forward_message(message_id: str):
    """Copy a message into another conversation.

    The copy records who originally wrote it, so a forwarded message cannot be
    passed off as the forwarder's own words.
    """
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    message = get_message_by_id(message_id)
    if message is None or message.get("deleted"):
        return jsonify({"error": "message not found"}), 404

    source = get_room_by_id(message.get("room_id", ""))
    if source is None or not _is_member(source, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    data = request.get_json(silent=True) or {}
    targets = data.get("room_ids") or ([data["room_id"]] if data.get("room_id") else [])
    if not targets:
        return jsonify({"error": "at least one destination room is required"}), 400

    created = []
    for target_id in targets[:10]:
        target = get_room_by_id(str(target_id))
        if target is None or not _is_member(target, username):
            continue
        if target.get("type") == "direct":
            others = [m for m in (target.get("members", []) or []) if m != username]
            if others and _is_blocked_between(username, others[0]):
                continue

        copy = {
            "id": str(uuid.uuid4()),
            "room_id": target.get("id"),
            "username": username,
            "text": message.get("text", ""),
            "attachment_url": message.get("attachment_url"),
            "attachment": message.get("attachment"),
            "forwarded_from": {
                "username": message.get("username"),
                "display_name": _display_name(message.get("username", "")),
            },
            "reply_to": None,
            "created_at": _now(),
            "edited_at": None,
            "deleted": False,
            "reactions": {},
        }
        save_message(copy)
        created.append(_serialize_message(copy, username))

    if not created:
        return jsonify({"error": "no reachable destination rooms"}), 400
    return jsonify(created), 201


@chat_bp.route("/api/chat/rooms/<room_id>/search", methods=["GET"])
def search_messages(room_id: str):
    """Find messages inside one conversation, newest first."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    query = str(request.args.get("q", "") or "").strip().lower()
    if len(query) < 2:
        return jsonify([]), 200

    hits = [
        m for m in get_messages_for_room(room_id)
        if not m.get("deleted") and query in (m.get("text", "") or "").lower()
    ]
    hits.sort(key=lambda m: m.get("created_at", ""), reverse=True)
    return jsonify([_serialize_message(m, username) for m in hits[:50]]), 200


@chat_bp.route("/api/chat/rooms/<room_id>/media", methods=["GET"])
def shared_media(room_id: str):
    """Every photo, video and file shared in this conversation, newest first."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    items = [
        m for m in get_messages_for_room(room_id)
        if not m.get("deleted") and m.get("attachment_url")
    ]
    items.sort(key=lambda m: m.get("created_at", ""), reverse=True)
    return jsonify([_serialize_message(m, username) for m in items[:200]]), 200


@chat_bp.route("/api/chat/rooms/<room_id>/typing", methods=["POST"])
def announce_typing(room_id: str):
    """Register that the viewer is typing. Expires on its own after a few seconds."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    _mark_typing(room_id, username)
    return jsonify({"message": "noted"}), 200


@chat_bp.route("/api/chat/rooms/<room_id>/typing", methods=["GET"])
def list_typing(room_id: str):
    """Who else is typing in this room right now."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    typists = _who_is_typing(room_id, username)
    return jsonify([
        {"username": u, "display_name": _display_name(u)} for u in typists
    ]), 200


@chat_bp.route("/api/chat/rooms/<room_id>/mute", methods=["POST"])
def toggle_mute(room_id: str):
    """Mute or unmute notifications for a conversation."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    if room_id == COMMUNITY_ROOM_ID:
        _ensure_community_room()
    room = get_room_by_id(room_id)
    if room is None:
        return jsonify({"error": "room not found"}), 404
    if not _is_member(room, username):
        return jsonify({"error": "you are not a member of this room"}), 403

    data = request.get_json(silent=True) or {}
    muted = set(room.get("muted_by", []) or [])
    # Absent "muted" means toggle, which keeps the button working without the
    # client having to track current state.
    want = data.get("muted")
    should_mute = (username not in muted) if want is None else bool(want)

    if should_mute:
        muted.add(username)
    else:
        muted.discard(username)

    updated = update_room(room_id, {"muted_by": sorted(muted)}) or room
    return jsonify(_serialize_room(updated, username)), 200


@chat_bp.route("/api/chat/blocks", methods=["GET"])
def list_blocks():
    """People the viewer has blocked."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    return jsonify([
        {
            "username": blocked,
            "display_name": _display_name(blocked),
            "avatar_url": _avatar_for(blocked),
        }
        for blocked in sorted(_blocked_by(username))
    ]), 200


@chat_bp.route("/api/chat/blocks", methods=["POST"])
def block_user():
    """Block someone, hiding their conversation and refusing further messages."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    target = str(data.get("username", "") or "").strip().lower()
    if not target:
        return jsonify({"error": "username is required"}), 400
    if target == username:
        return jsonify({"error": "you cannot block yourself"}), 400
    if get_user_by_username(target) is None:
        return jsonify({"error": "user not found"}), 404

    blocked = _blocked_by(username)
    blocked.add(target)
    update_user(username, {"blocked": sorted(blocked)})
    return jsonify({"message": "user blocked", "username": target}), 200


@chat_bp.route("/api/chat/blocks/<target>", methods=["DELETE"])
def unblock_user(target: str):
    """Reverse a block, restoring the conversation."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    blocked = _blocked_by(username)
    if target not in blocked:
        return jsonify({"error": "that user is not blocked"}), 404

    blocked.discard(target)
    update_user(username, {"blocked": sorted(blocked)})
    return jsonify({"message": "user unblocked", "username": target}), 200
