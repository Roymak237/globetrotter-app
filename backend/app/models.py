"""
app/models.py

Data models and file I/O helpers.

All persistent data is stored in JSON files under the /data directory.
  - data/users.json         – registered users
  - data/itineraries.json   – user itineraries
  - data/destinations.json  – static destination catalogue (seed data)
  - data/shares.json        – shared itinerary records
  - data/comments.json      – threaded destination comments and their votes
  - data/reviews.json       – star ratings for the app itself
  - data/notifications.json – per-user activity feed
  - data/submissions.json   – community-submitted destinations awaiting review
  - data/chat_rooms.json    – community room, groups and direct conversations
  - data/chat_messages.json – messages belonging to those rooms
  - data/ratings.json       – per-user star ratings for individual destinations
  - data/password_resets.json – short-lived reset codes
  - data/calls.json         – call history for the chat call log
  - data/locations.json     – last shared position per user, expiring
  - data/media/             – uploaded attachments and avatars (binary)
"""
import datetime
import json
import os
import threading

_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# DATA_DIR is overridable so the smoke tests can run against a throwaway
# directory instead of the developer's real accounts and trips. In Docker the
# same variable is already set by docker-entrypoint.sh, which keeps the two
# halves of the deployment reading from one agreed location.
DATA_DIR = os.environ.get("DATA_DIR") or os.path.join(_BASE_DIR, "data")

USERS_FILE = os.path.join(DATA_DIR, "users.json")
ITINERARIES_FILE = os.path.join(DATA_DIR, "itineraries.json")
DESTINATIONS_FILE = os.path.join(DATA_DIR, "destinations.json")
SHARES_FILE = os.path.join(DATA_DIR, "shares.json")
COMMENTS_FILE = os.path.join(DATA_DIR, "comments.json")
REVIEWS_FILE = os.path.join(DATA_DIR, "reviews.json")
NOTIFICATIONS_FILE = os.path.join(DATA_DIR, "notifications.json")
SUBMISSIONS_FILE = os.path.join(DATA_DIR, "submissions.json")
CHAT_ROOMS_FILE = os.path.join(DATA_DIR, "chat_rooms.json")
CHAT_MESSAGES_FILE = os.path.join(DATA_DIR, "chat_messages.json")
RATINGS_FILE = os.path.join(DATA_DIR, "ratings.json")
PASSWORD_RESETS_FILE = os.path.join(DATA_DIR, "password_resets.json")
CALLS_FILE = os.path.join(DATA_DIR, "calls.json")
LOCATIONS_FILE = os.path.join(DATA_DIR, "locations.json")

# Uploaded binaries live beside the JSON stores so a single Docker volume keeps
# the whole of a deployment's user data together.
MEDIA_DIR = os.path.join(DATA_DIR, "media")

# Chat writes are far more frequent than anything else in the app and several
# gunicorn threads can service the same room at once. A process-wide lock keeps
# a read-modify-write cycle from interleaving and losing messages.
_WRITE_LOCK = threading.RLock()


def _read_json(filepath: str) -> list:
    """Read *filepath* and return its contents as a list.

    Decoded as ``utf-8-sig`` so a byte order mark, which Windows editors and
    PowerShell add by default, is stripped instead of derailing the parse.
    """
    if not os.path.exists(filepath):
        return []
    with open(filepath, "r", encoding="utf-8-sig") as fh:
        content = fh.read().strip()
        if not content:
            return []
        return json.loads(content)


def _write_json(filepath: str, data: list) -> None:
    """Serialise *data* and write it to *filepath*.

    The write goes to a temporary file that is then moved into place, so a
    crash midway through cannot leave a half-written file behind.
    """
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    tmp_path = f"{filepath}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.replace(tmp_path, filepath)


# User helpers

def get_all_users() -> list:
    return _read_json(USERS_FILE)


def get_user_by_username(username: str) -> dict | None:
    users = get_all_users()
    for user in users:
        if user.get("username") == username:
            return user
    return None


def save_user(user: dict) -> None:
    users = get_all_users()
    users.append(user)
    _write_json(USERS_FILE, users)


def update_user(username: str, updates: dict) -> dict | None:
    users = get_all_users()
    for index, user in enumerate(users):
        if user.get("username") == username:
            updated = {**user, **updates}
            users[index] = updated
            _write_json(USERS_FILE, users)
            return updated
    return None


def update_username_references(old_username: str, new_username: str) -> dict | None:
    """Rename a user and preserve their itinerary/share relationships."""
    users = get_all_users()
    user = next(
        (entry for entry in users if entry.get("username") == old_username),
        None,
    )
    if user is None:
        return None

    renamed_user = {**user, "username": new_username}
    users[users.index(user)] = renamed_user
    _write_json(USERS_FILE, users)

    itineraries = get_all_itineraries()
    for itinerary in itineraries:
        if itinerary.get("username") == old_username:
            itinerary["username"] = new_username
    _write_json(ITINERARIES_FILE, itineraries)

    shares = get_all_shares()
    for share in shares:
        if share.get("owner") == old_username:
            share["owner"] = new_username
        if share.get("shared_with") == old_username:
            share["shared_with"] = new_username
    _write_json(SHARES_FILE, shares)

    return renamed_user


def delete_user_account(username: str) -> bool:
    """Delete a user and cascade their owned travel data and shares."""
    users = get_all_users()
    remaining_users = [user for user in users if user.get("username") != username]
    if len(remaining_users) == len(users):
        return False
    _write_json(USERS_FILE, remaining_users)

    itineraries = get_all_itineraries()
    deleted_itinerary_ids = {
        itinerary.get("id")
        for itinerary in itineraries
        if itinerary.get("username") == username
    }
    remaining_itineraries = [
        itinerary
        for itinerary in itineraries
        if itinerary.get("username") != username
    ]
    _write_json(ITINERARIES_FILE, remaining_itineraries)

    shares = get_all_shares()
    remaining_shares = [
        share
        for share in shares
        if share.get("owner") != username
        and share.get("shared_with") != username
        and share.get("itinerary_id") not in deleted_itinerary_ids
    ]
    _write_json(SHARES_FILE, remaining_shares)
    return True


# Destination helpers

def get_all_destinations() -> list:
    return _read_json(DESTINATIONS_FILE)


def get_destination_by_id(dest_id: str) -> dict | None:
    for dest in get_all_destinations():
        if dest.get("id") == dest_id:
            return dest
    return None


# Itinerary helpers

def get_all_itineraries() -> list:
    return _read_json(ITINERARIES_FILE)


def get_itineraries_for_user(username: str) -> list:
    return [it for it in get_all_itineraries() if it.get("username") == username]


def get_itinerary_by_id(itinerary_id: str) -> dict | None:
    for it in get_all_itineraries():
        if it.get("id") == itinerary_id:
            return it
    return None


def save_itinerary(itinerary: dict) -> None:
    itineraries = get_all_itineraries()
    itineraries.append(itinerary)
    _write_json(ITINERARIES_FILE, itineraries)


def update_itinerary(itinerary_id: str, updates: dict) -> dict | None:
    itineraries = get_all_itineraries()
    for idx, it in enumerate(itineraries):
        if it.get("id") == itinerary_id:
            updated = {**it, **updates}
            itineraries[idx] = updated
            _write_json(ITINERARIES_FILE, itineraries)
            return updated
    return None


def delete_itinerary(itinerary_id: str) -> bool:
    itineraries = get_all_itineraries()
    new_itineraries = [it for it in itineraries if it.get("id") != itinerary_id]
    if len(new_itineraries) == len(itineraries):
        return False
    _write_json(ITINERARIES_FILE, new_itineraries)
    return True


# Share helpers

def get_all_shares() -> list:
    return _read_json(SHARES_FILE)


def get_shares_for_itinerary(itinerary_id: str) -> list:
    return [s for s in get_all_shares() if s.get("itinerary_id") == itinerary_id]


def save_share(share: dict) -> None:
    shares = get_all_shares()
    shares.append(share)
    _write_json(SHARES_FILE, shares)


def delete_share(share_id: str) -> bool:
    shares = get_all_shares()
    new_shares = [s for s in shares if s.get("id") != share_id]
    if len(new_shares) == len(shares):
        return False
    _write_json(SHARES_FILE, new_shares)
    return True


# Comment helpers
#
# Comments are stored flat with a nullable ``parent_id``; the API assembles the
# reply tree on read. Keeping storage flat means a vote or an edit only has to
# touch one record.

def get_all_comments() -> list:
    return _read_json(COMMENTS_FILE)


def get_comments_for_destination(destination_id: str) -> list:
    return [
        c for c in get_all_comments()
        if c.get("destination_id") == destination_id
    ]


def get_comment_by_id(comment_id: str) -> dict | None:
    for comment in get_all_comments():
        if comment.get("id") == comment_id:
            return comment
    return None


def save_comment(comment: dict) -> None:
    with _WRITE_LOCK:
        comments = get_all_comments()
        comments.append(comment)
        _write_json(COMMENTS_FILE, comments)


def update_comment(comment_id: str, updates: dict) -> dict | None:
    with _WRITE_LOCK:
        comments = get_all_comments()
        for idx, comment in enumerate(comments):
            if comment.get("id") == comment_id:
                updated = {**comment, **updates}
                comments[idx] = updated
                _write_json(COMMENTS_FILE, comments)
                return updated
    return None


def delete_comment(comment_id: str) -> bool:
    """Remove *comment_id* along with every reply beneath it."""
    with _WRITE_LOCK:
        comments = get_all_comments()
        doomed = {comment_id}
        # Replies are only one level deep in the UI, but loop until the set
        # stops growing so deeper nesting can never orphan a record.
        while True:
            children = {
                c["id"] for c in comments
                if c.get("parent_id") in doomed and c["id"] not in doomed
            }
            if not children:
                break
            doomed |= children
        remaining = [c for c in comments if c.get("id") not in doomed]
        if len(remaining) == len(comments):
            return False
        _write_json(COMMENTS_FILE, remaining)
        return True


# App review helpers

def get_all_reviews() -> list:
    return _read_json(REVIEWS_FILE)


def get_review_by_username(username: str) -> dict | None:
    for review in get_all_reviews():
        if review.get("username") == username:
            return review
    return None


def save_or_update_review(review: dict) -> dict:
    """Upsert a review, since each user may only leave one."""
    with _WRITE_LOCK:
        reviews = get_all_reviews()
        for idx, existing in enumerate(reviews):
            if existing.get("username") == review.get("username"):
                merged = {**existing, **review}
                reviews[idx] = merged
                _write_json(REVIEWS_FILE, reviews)
                return merged
        reviews.append(review)
        _write_json(REVIEWS_FILE, reviews)
        return review


# Notification helpers

def get_notifications_for_user(username: str) -> list:
    return [
        n for n in _read_json(NOTIFICATIONS_FILE)
        if n.get("username") == username
    ]


def save_notification(notification: dict) -> None:
    with _WRITE_LOCK:
        notifications = _read_json(NOTIFICATIONS_FILE)
        notifications.append(notification)
        # The feed is display-only, so an unbounded file would grow forever for
        # no benefit. Keep the most recent slice.
        if len(notifications) > 2000:
            notifications = notifications[-2000:]
        _write_json(NOTIFICATIONS_FILE, notifications)


def mark_notifications_read(username: str, ids: list | None = None) -> int:
    """Mark the user's notifications read. ``None`` marks all of them."""
    with _WRITE_LOCK:
        notifications = _read_json(NOTIFICATIONS_FILE)
        changed = 0
        for notification in notifications:
            if notification.get("username") != username:
                continue
            if ids is not None and notification.get("id") not in ids:
                continue
            if not notification.get("read"):
                notification["read"] = True
                changed += 1
        if changed:
            _write_json(NOTIFICATIONS_FILE, notifications)
        return changed


# Submission helpers

def get_all_submissions() -> list:
    return _read_json(SUBMISSIONS_FILE)


def get_submissions_for_user(username: str) -> list:
    return [s for s in get_all_submissions() if s.get("username") == username]


def save_submission(submission: dict) -> None:
    with _WRITE_LOCK:
        submissions = get_all_submissions()
        submissions.append(submission)
        _write_json(SUBMISSIONS_FILE, submissions)


def update_submission(submission_id: str, updates: dict) -> dict | None:
    with _WRITE_LOCK:
        submissions = get_all_submissions()
        for idx, submission in enumerate(submissions):
            if submission.get("id") == submission_id:
                updated = {**submission, **updates}
                submissions[idx] = updated
                _write_json(SUBMISSIONS_FILE, submissions)
                return updated
    return None


# Chat helpers

def get_all_rooms() -> list:
    return _read_json(CHAT_ROOMS_FILE)


def get_room_by_id(room_id: str) -> dict | None:
    for room in get_all_rooms():
        if room.get("id") == room_id:
            return room
    return None


def save_room(room: dict) -> None:
    with _WRITE_LOCK:
        rooms = get_all_rooms()
        rooms.append(room)
        _write_json(CHAT_ROOMS_FILE, rooms)


def update_room(room_id: str, updates: dict) -> dict | None:
    with _WRITE_LOCK:
        rooms = get_all_rooms()
        for idx, room in enumerate(rooms):
            if room.get("id") == room_id:
                updated = {**room, **updates}
                rooms[idx] = updated
                _write_json(CHAT_ROOMS_FILE, rooms)
                return updated
    return None


def delete_room(room_id: str) -> bool:
    with _WRITE_LOCK:
        rooms = get_all_rooms()
        remaining = [r for r in rooms if r.get("id") != room_id]
        if len(remaining) == len(rooms):
            return False
        _write_json(CHAT_ROOMS_FILE, remaining)
        messages = get_all_messages()
        _write_json(
            CHAT_MESSAGES_FILE,
            [m for m in messages if m.get("room_id") != room_id],
        )
        return True


def get_all_messages() -> list:
    return _read_json(CHAT_MESSAGES_FILE)


def get_messages_for_room(room_id: str) -> list:
    return [m for m in get_all_messages() if m.get("room_id") == room_id]


def get_message_by_id(message_id: str) -> dict | None:
    for message in get_all_messages():
        if message.get("id") == message_id:
            return message
    return None


def save_message(message: dict) -> None:
    with _WRITE_LOCK:
        messages = get_all_messages()
        messages.append(message)
        _write_json(CHAT_MESSAGES_FILE, messages)


def update_message(message_id: str, updates: dict) -> dict | None:
    with _WRITE_LOCK:
        messages = get_all_messages()
        for idx, message in enumerate(messages):
            if message.get("id") == message_id:
                updated = {**message, **updates}
                messages[idx] = updated
                _write_json(CHAT_MESSAGES_FILE, messages)
                return updated
    return None


def get_room_by_invite_code(code: str) -> dict | None:
    """Look up a group by the share code printed on its invite link."""
    if not code:
        return None
    wanted = code.strip().upper()
    for room in get_all_rooms():
        if (room.get("invite_code") or "").upper() == wanted:
            return room
    return None


def get_rooms_for_user(username: str) -> list:
    """Rooms the user belongs to, excluding the always-visible community room."""
    return [
        room for room in get_all_rooms()
        if username in (room.get("members", []) or [])
    ]


# Destination rating helpers
#
# Ratings are kept apart from comments: a traveller may rate a place without
# writing anything, and the aggregate is read far more often than it is written.

def get_all_ratings() -> list:
    return _read_json(RATINGS_FILE)


def get_ratings_for_destination(destination_id: str) -> list:
    return [
        r for r in get_all_ratings()
        if r.get("destination_id") == destination_id
    ]


def get_rating(destination_id: str, username: str) -> dict | None:
    for rating in get_all_ratings():
        if (
            rating.get("destination_id") == destination_id
            and rating.get("username") == username
        ):
            return rating
    return None


def save_or_update_rating(rating: dict) -> dict:
    """Upsert a rating, since each user rates a destination at most once."""
    with _WRITE_LOCK:
        ratings = get_all_ratings()
        for idx, existing in enumerate(ratings):
            if (
                existing.get("destination_id") == rating.get("destination_id")
                and existing.get("username") == rating.get("username")
            ):
                merged = {**existing, **rating}
                ratings[idx] = merged
                _write_json(RATINGS_FILE, ratings)
                return merged
        ratings.append(rating)
        _write_json(RATINGS_FILE, ratings)
        return rating


def delete_rating(destination_id: str, username: str) -> bool:
    with _WRITE_LOCK:
        ratings = get_all_ratings()
        remaining = [
            r for r in ratings
            if not (
                r.get("destination_id") == destination_id
                and r.get("username") == username
            )
        ]
        if len(remaining) == len(ratings):
            return False
        _write_json(RATINGS_FILE, remaining)
        return True


def rating_summary(destination_id: str) -> dict:
    """Average and count for a destination, rounded for display."""
    values = [
        r.get("stars", 0) for r in get_ratings_for_destination(destination_id)
        if isinstance(r.get("stars"), int)
    ]
    if not values:
        return {"average": 0.0, "count": 0}
    return {"average": round(sum(values) / len(values), 1), "count": len(values)}


# Password reset helpers
#
# Codes are single-use and short-lived. Expired rows are cleared opportunistically
# on each write so the file cannot accumulate stale secrets.

def get_all_password_resets() -> list:
    return _read_json(PASSWORD_RESETS_FILE)


def save_password_reset(entry: dict) -> None:
    with _WRITE_LOCK:
        entries = get_all_password_resets()
        # Only the newest code for a given account stays valid.
        entries = [
            e for e in entries if e.get("username") != entry.get("username")
        ]
        entries.append(entry)
        _write_json(PASSWORD_RESETS_FILE, entries)


def pop_password_reset(username: str) -> dict | None:
    """Return and consume the pending reset for *username*, if any."""
    with _WRITE_LOCK:
        entries = get_all_password_resets()
        found = None
        remaining = []
        for entry in entries:
            if found is None and entry.get("username") == username:
                found = entry
            else:
                remaining.append(entry)
        if found is not None:
            _write_json(PASSWORD_RESETS_FILE, remaining)
        return found


def peek_password_reset(username: str) -> dict | None:
    for entry in get_all_password_resets():
        if entry.get("username") == username:
            return entry
    return None


# Call history helpers

def get_all_calls() -> list:
    return _read_json(CALLS_FILE)


def get_calls_for_user(username: str) -> list:
    return [
        c for c in get_all_calls()
        if username in (c.get("participants", []) or [])
    ]


def save_call(call: dict) -> None:
    with _WRITE_LOCK:
        calls = get_all_calls()
        calls.append(call)
        # The log is informational; keeping it bounded avoids unbounded growth.
        if len(calls) > 2000:
            calls = calls[-2000:]
        _write_json(CALLS_FILE, calls)


def update_call(call_id: str, updates: dict) -> dict | None:
    with _WRITE_LOCK:
        calls = get_all_calls()
        for idx, call in enumerate(calls):
            if call.get("id") == call_id:
                updated = {**call, **updates}
                calls[idx] = updated
                _write_json(CALLS_FILE, calls)
                return updated
    return None


# Shared location helpers
#
# This is the only store here that holds a physical fact about where a person
# actually is, so it is deliberately the most restrictive one in the file.
#
# Two rules do most of the privacy work, and both are enforced here rather than
# left to callers:
#
#   1. One record per user, replaced on every write. No history accumulates, so
#      there is no trail to reconstruct, leak or subpoena — not even by someone
#      with the data file in hand.
#   2. Records expire. A position is a claim about *now*, and a stale one is
#      worse than none: it sends people to where someone used to be. Anything
#      past the window is treated as absent and dropped on the next write.
#
# The window is short on purpose. Closing the app stops the updates, so a user
# disappears shortly afterwards without having to remember to switch anything
# off.
LOCATION_TTL_SECONDS = 30 * 60


def _location_is_live(record: dict, now: datetime.datetime) -> bool:
    """True when *record* is recent enough to still describe where someone is."""
    stamp = record.get("updated_at")
    if not isinstance(stamp, str):
        return False
    try:
        seen = datetime.datetime.fromisoformat(stamp)
    except ValueError:
        # An unparseable timestamp cannot be shown to be recent, and the safe
        # reading of "unknown age" is "too old".
        return False
    if seen.tzinfo is None:
        seen = seen.replace(tzinfo=datetime.timezone.utc)
    return (now - seen).total_seconds() < LOCATION_TTL_SECONDS


def get_live_locations() -> list:
    """Every position still inside the expiry window."""
    now = datetime.datetime.now(datetime.timezone.utc)
    return [r for r in _read_json(LOCATIONS_FILE) if _location_is_live(r, now)]


def get_location_for_user(username: str) -> dict | None:
    for record in get_live_locations():
        if record.get("username") == username:
            return record
    return None


def save_location(record: dict) -> dict:
    """Store *record* as the user's only position, pruning expired ones.

    Writing is when the file is already being rewritten, so it is also the
    cheapest moment to drop everything stale. That means expired positions
    leave the disk as a matter of course, instead of lingering until someone
    remembers to run a cleanup.
    """
    username = record.get("username")
    now = datetime.datetime.now(datetime.timezone.utc)
    with _WRITE_LOCK:
        kept = [
            r for r in _read_json(LOCATIONS_FILE)
            if r.get("username") != username and _location_is_live(r, now)
        ]
        kept.append(record)
        _write_json(LOCATIONS_FILE, kept)
    return record


def delete_location(username: str) -> bool:
    """Erase the user's position. Returns True when there was one to erase."""
    now = datetime.datetime.now(datetime.timezone.utc)
    with _WRITE_LOCK:
        records = _read_json(LOCATIONS_FILE)
        kept = [
            r for r in records
            if r.get("username") != username and _location_is_live(r, now)
        ]
        removed = any(r.get("username") == username for r in records)
        if len(kept) != len(records):
            _write_json(LOCATIONS_FILE, kept)
    return removed


