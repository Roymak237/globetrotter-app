"""
app/social.py

The community layer that sits on top of the destination catalogue: threaded
comments with voting, and star reviews of the app itself.

Routes
------
GET    /api/destinations/<dest_id>/comments   List the comment tree
POST   /api/destinations/<dest_id>/comments   Post a comment or a reply
PATCH  /api/comments/<comment_id>             Edit your own comment
DELETE /api/comments/<comment_id>             Delete your own comment and replies
POST   /api/comments/<comment_id>/vote        Up/down vote, or clear your vote
GET    /api/app-reviews                       Aggregate rating plus recent reviews
PUT    /api/app-reviews                       Create or replace your own review
"""
import datetime
import uuid

from flask import Blueprint, jsonify, request

from app.auth import get_current_user
from app.models import (
    delete_comment,
    get_comment_by_id,
    get_comments_for_destination,
    get_destination_by_id,
    get_all_reviews,
    get_review_by_username,
    get_user_by_username,
    save_comment,
    save_notification,
    save_or_update_review,
    update_comment,
)

social_bp = Blueprint("social", __name__)

MAX_COMMENT_LENGTH = 1000
MAX_FEEDBACK_LENGTH = 500


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _avatar_for(username: str) -> str:
    user = get_user_by_username(username)
    return (user or {}).get("avatar_url", "") or ""


def _score(comment: dict) -> int:
    """Net score: upvotes minus downvotes."""
    votes = comment.get("votes", {}) or {}
    return sum(1 for v in votes.values() if v == 1) - sum(
        1 for v in votes.values() if v == -1
    )


def _serialize(comment: dict, viewer: str | None, children: dict) -> dict:
    """Shape a stored comment for the client, nesting its replies."""
    votes = comment.get("votes", {}) or {}
    replies = sorted(
        children.get(comment["id"], []),
        key=lambda c: c.get("created_at", ""),
    )
    return {
        "id": comment.get("id"),
        "destination_id": comment.get("destination_id"),
        "parent_id": comment.get("parent_id"),
        "username": comment.get("username"),
        "avatar_url": _avatar_for(comment.get("username", "")),
        "text": comment.get("text", ""),
        "created_at": comment.get("created_at"),
        "edited_at": comment.get("edited_at"),
        "score": _score(comment),
        # The viewer's own vote drives the highlighted arrow in the UI.
        "user_vote": votes.get(viewer) if viewer else None,
        "replies": [_serialize(child, viewer, children) for child in replies],
    }


@social_bp.route("/api/destinations/<dest_id>/comments", methods=["GET"])
def list_comments(dest_id: str):
    """Return the comment tree for a destination, newest thread first."""
    if get_destination_by_id(dest_id) is None:
        return jsonify({"error": "destination not found"}), 404

    viewer = get_current_user(request)
    comments = get_comments_for_destination(dest_id)

    # Bucket replies by parent once, so serialising the tree stays linear
    # rather than rescanning the whole list at every level.
    children: dict = {}
    for comment in comments:
        parent_id = comment.get("parent_id")
        if parent_id:
            children.setdefault(parent_id, []).append(comment)

    roots = sorted(
        (c for c in comments if not c.get("parent_id")),
        key=lambda c: c.get("created_at", ""),
        reverse=True,
    )
    return jsonify([_serialize(root, viewer, children) for root in roots]), 200


@social_bp.route("/api/destinations/<dest_id>/comments", methods=["POST"])
def create_comment(dest_id: str):
    """Post a top-level comment, or a reply when ``parent_id`` is supplied."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401
    if get_destination_by_id(dest_id) is None:
        return jsonify({"error": "destination not found"}), 404

    data = request.get_json(silent=True) or {}
    text = str(data.get("text", "")).strip()
    if not text:
        return jsonify({"error": "comment text is required"}), 400
    if len(text) > MAX_COMMENT_LENGTH:
        return jsonify(
            {"error": f"comment must be {MAX_COMMENT_LENGTH} characters or fewer"}
        ), 400

    parent_id = data.get("parent_id") or None
    parent = None
    if parent_id:
        parent = get_comment_by_id(parent_id)
        if parent is None or parent.get("destination_id") != dest_id:
            return jsonify({"error": "parent comment not found"}), 404
        # Replies are kept one level deep so the thread stays readable on a
        # phone; replying to a reply attaches to the same root.
        parent_id = parent.get("parent_id") or parent_id

    comment = {
        "id": str(uuid.uuid4()),
        "destination_id": dest_id,
        "parent_id": parent_id,
        "username": username,
        "text": text,
        "created_at": _now(),
        "edited_at": None,
        "votes": {},
    }
    save_comment(comment)

    # Tell the parent's author someone replied, but never notify yourself.
    if parent and parent.get("username") != username:
        destination = get_destination_by_id(dest_id) or {}
        save_notification({
            "id": str(uuid.uuid4()),
            "username": parent.get("username"),
            "type": "reply",
            "actor": username,
            "destination_id": dest_id,
            "comment_id": comment["id"],
            "text": f"{username} replied to you on {destination.get('name', 'a destination')}",
            "created_at": _now(),
            "read": False,
        })

    return jsonify(_serialize(comment, username, {})), 201


@social_bp.route("/api/comments/<comment_id>", methods=["PATCH"])
def edit_comment(comment_id: str):
    """Edit your own comment."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    comment = get_comment_by_id(comment_id)
    if comment is None:
        return jsonify({"error": "comment not found"}), 404
    if comment.get("username") != username:
        return jsonify({"error": "you can only edit your own comments"}), 403

    data = request.get_json(silent=True) or {}
    text = str(data.get("text", "")).strip()
    if not text:
        return jsonify({"error": "comment text is required"}), 400
    if len(text) > MAX_COMMENT_LENGTH:
        return jsonify(
            {"error": f"comment must be {MAX_COMMENT_LENGTH} characters or fewer"}
        ), 400

    updated = update_comment(comment_id, {"text": text, "edited_at": _now()})
    return jsonify(_serialize(updated, username, {})), 200


@social_bp.route("/api/comments/<comment_id>", methods=["DELETE"])
def remove_comment(comment_id: str):
    """Delete your own comment along with any replies to it."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    comment = get_comment_by_id(comment_id)
    if comment is None:
        return jsonify({"error": "comment not found"}), 404
    if comment.get("username") != username:
        return jsonify({"error": "you can only delete your own comments"}), 403

    delete_comment(comment_id)
    return jsonify({"message": "comment deleted"}), 200


@social_bp.route("/api/comments/<comment_id>/vote", methods=["POST"])
def vote_comment(comment_id: str):
    """Record a vote of 1 or -1, or 0 to clear the viewer's existing vote."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    comment = get_comment_by_id(comment_id)
    if comment is None:
        return jsonify({"error": "comment not found"}), 404

    data = request.get_json(silent=True) or {}
    try:
        value = int(data.get("value", 0))
    except (TypeError, ValueError):
        return jsonify({"error": "value must be 1, -1, or 0"}), 400
    if value not in (1, -1, 0):
        return jsonify({"error": "value must be 1, -1, or 0"}), 400

    votes = dict(comment.get("votes", {}) or {})
    if value == 0:
        votes.pop(username, None)
    else:
        votes[username] = value

    updated = update_comment(comment_id, {"votes": votes})
    return jsonify(_serialize(updated, username, {})), 200


@social_bp.route("/api/app-reviews", methods=["GET"])
def list_app_reviews():
    """Return the aggregate star rating and the most recent written reviews."""
    reviews = get_all_reviews()
    stars = [int(r.get("stars", 0)) for r in reviews if r.get("stars")]
    average = round(sum(stars) / len(stars), 2) if stars else 0.0

    recent = sorted(
        reviews, key=lambda r: r.get("created_at", ""), reverse=True
    )[:20]
    viewer = get_current_user(request)
    mine = get_review_by_username(viewer) if viewer else None

    return jsonify({
        "average": average,
        "count": len(stars),
        "mine": mine,
        "reviews": [
            {
                "username": r.get("username"),
                "avatar_url": _avatar_for(r.get("username", "")),
                "stars": r.get("stars"),
                "feedback": r.get("feedback"),
                "created_at": r.get("created_at"),
                "updated_at": r.get("updated_at"),
            }
            for r in recent
        ],
    }), 200


@social_bp.route("/api/app-reviews", methods=["PUT"])
def upsert_app_review():
    """Create or replace the current user's review of the app."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    data = request.get_json(silent=True) or {}
    try:
        stars = int(data.get("stars", 0))
    except (TypeError, ValueError):
        return jsonify({"error": "stars must be a whole number from 1 to 5"}), 400
    if not 1 <= stars <= 5:
        return jsonify({"error": "stars must be a whole number from 1 to 5"}), 400

    feedback = str(data.get("feedback", "") or "").strip()
    if len(feedback) > MAX_FEEDBACK_LENGTH:
        return jsonify(
            {"error": f"feedback must be {MAX_FEEDBACK_LENGTH} characters or fewer"}
        ), 400

    existing = get_review_by_username(username)
    review = {
        "username": username,
        "stars": stars,
        "feedback": feedback or None,
        "created_at": (existing or {}).get("created_at") or _now(),
        "updated_at": _now() if existing else None,
    }
    save_or_update_review(review)
    return jsonify(review), 200
