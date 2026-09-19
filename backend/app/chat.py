"""
app/chat.py

Trip Chat: a community room every traveller shares, private one-to-one
conversations, and invite-only groups.

Delivery is poll-based rather than websocket-based. Gunicorn runs synchronous
workers here, so a long-lived socket per client would pin a worker; a cheap
``since`` cursor gives near-live updates without that cost.

Routes
------
GET    /api/chat/rooms                     Rooms visible to the viewer
POST   /api/chat/rooms                     Create a group
GET    /api/chat/rooms/<room_id>/messages  Messages, optionally since a cursor
POST   /api/chat/rooms/<room_id>/messages  Post a message
POST   /api/chat/rooms/<room_id>/read      Move the viewer's read cursor
POST   /api/chat/rooms/<room_id>/members   Add someone to a group
DELETE /api/chat/rooms/<room_id>/members   Leave a group
POST   /api/chat/direct                    Open (or reuse) a direct conversation
POST   /api/chat/messages/<message_id>/reactions  Toggle an emoji reaction
DELETE /api/chat/messages/<message_id>     Delete your own message
GET    /api/chat/users/search              Find people to talk to
"""
import datetime
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
)

chat_bp = Blueprint("chat", __name__)

COMMUNITY_ROOM_ID = "community"
MAX_MESSAGE_LENGTH = 2000
MAX_ROOM_NAME_LENGTH = 80
MESSAGE_PAGE_SIZE = 200


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


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
                "text": (parent.get("text", "") or "")[:140],
                "deleted": bool(parent.get("deleted")),
            }

    deleted = bool(message.get("deleted"))
    return {
        "id": message.get("id"),
        "room_id": message.get("room_id"),
        "username": message.get("username"),
        "display_name": _display_name(message.get("username", "")),
        "avatar_url": _avatar_for(message.get("username", "")),
        "text": "" if deleted else message.get("text", ""),
        "attachment_url": None if deleted else message.get("attachment_url"),
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
    if room.get("type") == "direct":
        # A direct conversation is labelled with whoever you are talking to.
        others = [m for m in (room.get("members", []) or []) if m != viewer]
        if others:
            name = _display_name(others[0])
            avatar = _avatar_for(others[0])

    last = messages[-1] if messages else None
    return {
        "id": room.get("id"),
        "type": room.get("type"),
        "name": name,
        "avatar_url": avatar,
        "description": room.get("description", ""),
        "members": room.get("members", []) or [],
        "member_count": len(room.get("members", []) or []),
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
    visible = [r for r in get_all_rooms() if _is_member(r, username)]
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
        "created_by": username,
        "members": sorted(members),
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

    data = request.get_json(silent=True) or {}
    text = str(data.get("text", "") or "").strip()
    attachment_url = str(data.get("attachment_url", "") or "").strip()
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
        "reply_to": reply_to,
        "created_at": _now(),
        "edited_at": None,
        "deleted": False,
        "reactions": {},
    }
    save_message(message)

    # Direct messages are the one place a notification is worth the noise.
    if room.get("type") == "direct":
        for member in room.get("members", []) or []:
            if member == username:
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
