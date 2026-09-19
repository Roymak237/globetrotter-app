"""
app/groups.py

Group administration for Trip Chat: invite links, join requests, member roles
and the group profile itself.

Two ways in, deliberately:

* An **invite code** is a capability. Anyone holding it joins immediately, which
  suits a code pasted into a WhatsApp thread among people who already know each
  other.
* A **join request** is a petition. It lands in a queue an admin approves or
  declines, which suits someone who found the group from the inside of the app.

Admins can rotate the invite code, which is the only way to revoke a code that
has leaked beyond its intended audience.

Routes
------
PATCH  /api/chat/groups/<room_id>                 Rename or re-describe a group
POST   /api/chat/groups/<room_id>/invite/rotate   Issue a fresh invite code
POST   /api/chat/groups/join                      Join using an invite code
POST   /api/chat/groups/<room_id>/requests        Ask to join a group
GET    /api/chat/groups/<room_id>/requests        Pending requests (admins)
POST   /api/chat/groups/<room_id>/requests/<user> Approve or decline a request
POST   /api/chat/groups/<room_id>/admins          Promote a member to admin
DELETE /api/chat/groups/<room_id>/admins/<user>   Demote an admin
DELETE /api/chat/groups/<room_id>/members/<user>  Remove a member
GET    /api/chat/groups/<room_id>/members         Member list with roles
GET    /api/chat/groups/discover                  Groups you could ask to join
"""
import datetime
import uuid

from flask import Blueprint, jsonify, request

from app.auth import get_current_user
from app.chat import (
    MAX_ROOM_NAME_LENGTH,
    _avatar_for,
    _display_name,
    _is_admin,
    _new_invite_code,
    _serialize_room,
)
from app.models import (
    get_all_rooms,
    get_room_by_id,
    get_room_by_invite_code,
    get_user_by_username,
    save_notification,
    update_room,
)

groups_bp = Blueprint("groups", __name__)

MAX_DESCRIPTION_LENGTH = 300


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _notify(username: str, kind: str, actor: str, room: dict, text: str) -> None:
    save_notification({
        "id": str(uuid.uuid4()),
        "username": username,
        "type": kind,
        "actor": actor,
        "room_id": room.get("id"),
        "text": text,
        "created_at": _now(),
        "read": False,
    })


def _require_group(room_id: str) -> tuple[dict | None, tuple]:
    """Fetch a room and confirm it is a group, or produce the error response."""
    room = get_room_by_id(room_id)
    if room is None:
        return None, (jsonify({"error": "group not found"}), 404)
    if room.get("type") != "group":
        return None, (jsonify({"error": "that conversation is not a group"}), 400)
    return room, ()


@groups_bp.route("/api/chat/groups/<room_id>", methods=["PATCH"])
def edit_group(room_id: str):
    """Rename a group or change its description or photo. Admins only."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error
    if not _is_admin(room, username):
        return jsonify({"error": "only group admins can do that"}), 403

    data = request.get_json(silent=True) or {}
    updates = {}

    if "name" in data:
        name = str(data.get("name", "") or "").strip()
        if not name:
            return jsonify({"error": "name is required"}), 400
        if len(name) > MAX_ROOM_NAME_LENGTH:
            return jsonify(
                {"error": f"name must be {MAX_ROOM_NAME_LENGTH} characters or fewer"}
            ), 400
        updates["name"] = name

    if "description" in data:
        description = str(data.get("description", "") or "").strip()
        if len(description) > MAX_DESCRIPTION_LENGTH:
            return jsonify(
                {"error": f"description must be {MAX_DESCRIPTION_LENGTH} characters or fewer"}
            ), 400
        updates["description"] = description

    if "avatar_url" in data:
        avatar = str(data.get("avatar_url", "") or "").strip()
        # Same restriction as chat attachments: our own media only.
        if avatar and not avatar.startswith("/api/media/"):
            return jsonify({"error": "avatar must be an uploaded image"}), 400
        updates["avatar_url"] = avatar

    if not updates:
        return jsonify({"error": "nothing to update"}), 400

    updated = update_room(room_id, updates) or room
    return jsonify(_serialize_room(updated, username)), 200


@groups_bp.route("/api/chat/groups/<room_id>/invite/rotate", methods=["POST"])
def rotate_invite(room_id: str):
    """Replace the invite code, invalidating any copy already circulating."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error
    if not _is_admin(room, username):
        return jsonify({"error": "only group admins can do that"}), 403

    code = _new_invite_code()
    updated = update_room(room_id, {"invite_code": code}) or room
    return jsonify({"invite_code": code, "room": _serialize_room(updated, username)}), 200


@groups_bp.route("/api/chat/groups/join", methods=["POST"])
def join_with_code():
    """Join a group using an invite code."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    code = str(data.get("code", "") or "").strip()
    if not code:
        return jsonify({"error": "an invite code is required"}), 400

    room = get_room_by_invite_code(code)
    if room is None or room.get("type") != "group":
        return jsonify({"error": "that invite code is not valid"}), 404

    members = list(room.get("members", []) or [])
    if username in members:
        return jsonify(_serialize_room(room, username)), 200

    members.append(username)
    # Joining by code clears any outstanding request from the same person, so
    # an admin is not left approving someone who is already inside.
    requests_left = [
        r for r in (room.get("join_requests", []) or [])
        if r.get("username") != username
    ]
    updated = update_room(
        room_id := room["id"],
        {"members": sorted(members), "join_requests": requests_left},
    ) or room

    for admin in set(updated.get("admins", []) or []) | {updated.get("created_by")}:
        if admin and admin != username:
            _notify(
                admin, "group_join", username, updated,
                f"{_display_name(username)} joined {updated.get('name', 'your group')}",
            )

    return jsonify(_serialize_room(updated, username)), 200


@groups_bp.route("/api/chat/groups/<room_id>/requests", methods=["POST"])
def request_to_join(room_id: str):
    """Ask a group's admins for admission."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error

    if username in (room.get("members", []) or []):
        return jsonify({"error": "you are already in this group"}), 400

    pending = list(room.get("join_requests", []) or [])
    if any(r.get("username") == username for r in pending):
        return jsonify({"message": "your request is already pending"}), 200

    data = request.get_json(silent=True) or {}
    pending.append({
        "username": username,
        "message": str(data.get("message", "") or "").strip()[:200],
        "created_at": _now(),
    })
    updated = update_room(room_id, {"join_requests": pending}) or room

    for admin in set(updated.get("admins", []) or []) | {updated.get("created_by")}:
        if admin and admin != username:
            _notify(
                admin, "join_request", username, updated,
                f"{_display_name(username)} asked to join {updated.get('name', 'your group')}",
            )

    return jsonify({"message": "request sent"}), 201


@groups_bp.route("/api/chat/groups/<room_id>/requests", methods=["GET"])
def list_requests(room_id: str):
    """Pending join requests. Admins only."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error
    if not _is_admin(room, username):
        return jsonify({"error": "only group admins can do that"}), 403

    return jsonify([
        {
            "username": entry.get("username"),
            "display_name": _display_name(entry.get("username", "")),
            "avatar_url": _avatar_for(entry.get("username", "")),
            "message": entry.get("message", ""),
            "created_at": entry.get("created_at"),
        }
        for entry in (room.get("join_requests", []) or [])
    ]), 200


@groups_bp.route("/api/chat/groups/<room_id>/requests/<target>", methods=["POST"])
def respond_to_request(room_id: str, target: str):
    """Approve or decline a pending request. Admins only."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error
    if not _is_admin(room, username):
        return jsonify({"error": "only group admins can do that"}), 403

    pending = list(room.get("join_requests", []) or [])
    if not any(r.get("username") == target for r in pending):
        return jsonify({"error": "no pending request from that user"}), 404

    data = request.get_json(silent=True) or {}
    approve = bool(data.get("approve", True))

    remaining = [r for r in pending if r.get("username") != target]
    updates = {"join_requests": remaining}

    if approve:
        members = list(room.get("members", []) or [])
        if target not in members:
            members.append(target)
        updates["members"] = sorted(members)

    updated = update_room(room_id, updates) or room

    _notify(
        target,
        "join_approved" if approve else "join_declined",
        username,
        updated,
        f"You were added to {updated.get('name', 'the group')}" if approve
        else f"Your request to join {updated.get('name', 'the group')} wasn't approved",
    )

    return jsonify(_serialize_room(updated, username)), 200


@groups_bp.route("/api/chat/groups/<room_id>/admins", methods=["POST"])
def promote_admin(room_id: str):
    """Give an existing member admin rights."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error
    if not _is_admin(room, username):
        return jsonify({"error": "only group admins can do that"}), 403

    data = request.get_json(silent=True) or {}
    target = str(data.get("username", "") or "").strip().lower()
    if target not in (room.get("members", []) or []):
        return jsonify({"error": "that person is not in this group"}), 404

    admins = set(room.get("admins", []) or [])
    admins.add(target)
    updated = update_room(room_id, {"admins": sorted(admins)}) or room

    _notify(
        target, "group_admin", username, updated,
        f"You are now an admin of {updated.get('name', 'the group')}",
    )
    return jsonify(_serialize_room(updated, username)), 200


@groups_bp.route("/api/chat/groups/<room_id>/admins/<target>", methods=["DELETE"])
def demote_admin(room_id: str, target: str):
    """Remove admin rights. The creator's rights are permanent."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error
    if not _is_admin(room, username):
        return jsonify({"error": "only group admins can do that"}), 403
    if target == room.get("created_by"):
        return jsonify({"error": "the group creator cannot be demoted"}), 400

    admins = set(room.get("admins", []) or [])
    admins.discard(target)
    updated = update_room(room_id, {"admins": sorted(admins)}) or room
    return jsonify(_serialize_room(updated, username)), 200


@groups_bp.route("/api/chat/groups/<room_id>/members/<target>", methods=["DELETE"])
def remove_member(room_id: str, target: str):
    """Remove someone from a group. Admins only, and never the creator."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error
    if not _is_admin(room, username):
        return jsonify({"error": "only group admins can do that"}), 403
    if target == room.get("created_by"):
        return jsonify({"error": "the group creator cannot be removed"}), 400
    if target not in (room.get("members", []) or []):
        return jsonify({"error": "that person is not in this group"}), 404

    members = [m for m in (room.get("members", []) or []) if m != target]
    admins = [a for a in (room.get("admins", []) or []) if a != target]
    updated = update_room(
        room_id, {"members": members, "admins": admins}
    ) or room

    _notify(
        target, "group_removed", username, updated,
        f"You were removed from {updated.get('name', 'the group')}",
    )
    return jsonify(_serialize_room(updated, username)), 200


@groups_bp.route("/api/chat/groups/<room_id>/members", methods=["GET"])
def list_members(room_id: str):
    """Members with their roles, admins first then alphabetical."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    room, error = _require_group(room_id)
    if room is None:
        return error
    if username not in (room.get("members", []) or []):
        return jsonify({"error": "you are not a member of this group"}), 403

    creator = room.get("created_by")
    admins = set(room.get("admins", []) or [])
    if creator:
        admins.add(creator)

    people = [
        {
            "username": member,
            "display_name": _display_name(member),
            "avatar_url": _avatar_for(member),
            "bio": (get_user_by_username(member) or {}).get("bio", ""),
            "is_admin": member in admins,
            "is_creator": member == creator,
        }
        for member in (room.get("members", []) or [])
    ]
    people.sort(key=lambda p: (not p["is_creator"], not p["is_admin"], p["username"]))
    return jsonify(people), 200


@groups_bp.route("/api/chat/groups/discover", methods=["GET"])
def discover_groups():
    """Groups the viewer is not in yet, so there is a way in without a code."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    query = str(request.args.get("q", "") or "").strip().lower()

    results = []
    for room in get_all_rooms():
        if room.get("type") != "group":
            continue
        members = room.get("members", []) or []
        if username in members:
            continue
        haystack = f"{room.get('name', '')} {room.get('description', '')}".lower()
        if query and query not in haystack:
            continue
        results.append({
            "id": room.get("id"),
            "name": room.get("name", ""),
            "description": room.get("description", ""),
            "avatar_url": room.get("avatar_url", "") or "",
            "member_count": len(members),
            "requested": any(
                r.get("username") == username
                for r in (room.get("join_requests", []) or [])
            ),
        })

    results.sort(key=lambda r: r["member_count"], reverse=True)
    return jsonify(results[:50]), 200
