"""
app/media.py

Binary uploads: chat attachments, voice notes and profile avatars.

Files are stored on disk under ``data/media`` rather than as base64 inside the
JSON stores. Embedding binaries in those files would bloat every unrelated read
of a room or a user, and the whole point of the JSON layer is that it stays
cheap to scan.

Stored names are generated, never taken from the client. The original filename
travels separately in the message record, so a hostile upload cannot escape the
media directory or overwrite a neighbour.

Routes
------
POST /api/media                   Upload a file, returns its public URL
POST /api/media/<file_id>/ticket  Short-lived signed URL for playback
GET  /api/media/<file_id>         Stream a stored file back
"""
import datetime
import mimetypes
import os
import uuid

import jwt
from flask import Blueprint, current_app, jsonify, request, send_file

from app.auth import get_current_user
from app.models import MEDIA_DIR

media_bp = Blueprint("media", __name__)

# How long a playback ticket stays valid. Long enough to start and scrub a
# long voice note, short enough that a copied URL is not a lasting handout.
TICKET_TTL_SECONDS = 300

# Kept in step with ``client_max_body_size`` in both nginx layers. Raising this
# without raising those will surface as an opaque 413 from the proxy.
MAX_UPLOAD_BYTES = 10 * 1024 * 1024

# Allow-list rather than deny-list: anything not named here is rejected. The
# extension is chosen from this table too, so the stored name never echoes
# attacker-controlled text.
ALLOWED_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/gif": ".gif",
    "image/webp": ".webp",
    "video/mp4": ".mp4",
    "video/webm": ".webm",
    "video/quicktime": ".mov",
    "audio/mpeg": ".mp3",
    "audio/mp4": ".m4a",
    "audio/aac": ".aac",
    "audio/ogg": ".ogg",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/webm": ".webm",
    "application/pdf": ".pdf",
}

KIND_BY_PREFIX = {
    "image/": "image",
    "video/": "video",
    "audio/": "audio",
}

# Reverse of ALLOWED_TYPES, for naming the type of a file already on disk.
# ``.webm`` maps to both video and audio in ALLOWED_TYPES; video wins here
# because a browser given video/webm for an audio-only stream still plays it,
# whereas the reverse shows nothing.
EXTENSION_TYPES = {
    ".jpg": "image/jpeg",
    ".png": "image/png",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".mov": "video/quicktime",
    ".mp3": "audio/mpeg",
    ".m4a": "audio/mp4",
    ".aac": "audio/aac",
    ".ogg": "audio/ogg",
    ".wav": "audio/wav",
    ".pdf": "application/pdf",
}


def _kind_for(content_type: str) -> str:
    for prefix, kind in KIND_BY_PREFIX.items():
        if content_type.startswith(prefix):
            return kind
    return "file"


def _ensure_media_dir() -> None:
    os.makedirs(MEDIA_DIR, exist_ok=True)


def _resolve_stored_path(file_id: str) -> str | None:
    """Map a file id to a path inside MEDIA_DIR, or ``None`` if it escapes.

    ``file_id`` arrives from the URL, so it is treated as hostile: the resolved
    path must still sit inside the media directory after normalisation.
    """
    if not file_id or "/" in file_id or "\\" in file_id or file_id.startswith("."):
        return None
    candidate = os.path.abspath(os.path.join(MEDIA_DIR, file_id))
    root = os.path.abspath(MEDIA_DIR)
    if not candidate.startswith(root + os.sep):
        return None
    if not os.path.isfile(candidate):
        return None
    return candidate


@media_bp.route("/api/media", methods=["POST"])
def upload_media():
    """Accept one file and return the URL the app should reference."""
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    uploaded = request.files.get("file")
    if uploaded is None or not uploaded.filename:
        return jsonify({"error": "a file is required"}), 400

    content_type = (uploaded.mimetype or "").split(";")[0].strip().lower()
    # Browsers occasionally send a blank or generic type for recorded audio, so
    # fall back to sniffing the filename before rejecting the upload.
    if content_type not in ALLOWED_TYPES:
        guessed, _ = mimetypes.guess_type(uploaded.filename)
        if guessed in ALLOWED_TYPES:
            content_type = guessed
    if content_type not in ALLOWED_TYPES:
        return jsonify({"error": f"unsupported file type: {content_type or 'unknown'}"}), 400

    # Measure by seeking rather than reading the whole upload into memory.
    uploaded.stream.seek(0, os.SEEK_END)
    size = uploaded.stream.tell()
    uploaded.stream.seek(0)
    if size <= 0:
        return jsonify({"error": "the file is empty"}), 400
    if size > MAX_UPLOAD_BYTES:
        limit_mb = MAX_UPLOAD_BYTES // (1024 * 1024)
        return jsonify({"error": f"file must be {limit_mb} MB or smaller"}), 413

    _ensure_media_dir()
    file_id = f"{uuid.uuid4().hex}{ALLOWED_TYPES[content_type]}"
    uploaded.save(os.path.join(MEDIA_DIR, file_id))

    return jsonify({
        "id": file_id,
        "url": f"/api/media/{file_id}",
        "kind": _kind_for(content_type),
        "content_type": content_type,
        "size": size,
        "filename": os.path.basename(uploaded.filename)[:120],
        "uploaded_by": username,
        "uploaded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }), 201


@media_bp.route("/api/media/<file_id>/ticket", methods=["POST"])
def media_ticket(file_id: str):
    """Issue a short-lived signed URL for playing one stored file.

    The Flutter client asks for this before opening the audio or video
    player, because a ``<video>`` element cannot carry an Authorization
    header. Without this route the player received a 404 and every voice
    note and video attachment failed to open.

    Signed with the same JWT secret as session tokens, so no server-side
    state is needed and a forged or expired ticket is detectable.
    """
    username = get_current_user(request)
    if username is None:
        return jsonify({"error": "authentication required"}), 401

    path = _resolve_stored_path(file_id)
    if path is None:
        return jsonify({"error": "file not found"}), 404

    now = datetime.datetime.now(datetime.timezone.utc)
    ticket = jwt.encode(
        {
            "sub": username,
            "fid": file_id,
            "iat": now,
            "exp": now + datetime.timedelta(seconds=TICKET_TTL_SECONDS),
        },
        current_app.config["SECRET_KEY"],
        algorithm="HS256",
    )
    return jsonify({
        "url": f"/api/media/{file_id}?ticket={ticket}",
        "expires_in": TICKET_TTL_SECONDS,
    }), 200


def _ticket_rejection(file_id: str):
    """Validate a ``ticket`` query parameter if one was supplied.

    Returns an error response, or ``None`` when the request may proceed.
    A missing ticket is allowed: these URLs are also used in ``<img>`` tags
    that cannot be given one, and the identifiers are unguessable random
    hex. A ticket that *is* present must be real, otherwise presenting a
    tampered one would be quietly equivalent to presenting none.
    """
    ticket = request.args.get("ticket")
    if not ticket:
        return None
    try:
        payload = jwt.decode(
            ticket, current_app.config["SECRET_KEY"], algorithms=["HS256"]
        )
    except jwt.ExpiredSignatureError:
        return jsonify({"error": "this media link has expired"}), 403
    except jwt.PyJWTError:
        return jsonify({"error": "invalid media link"}), 403
    # A ticket for one file must not unlock another.
    if payload.get("fid") != file_id:
        return jsonify({"error": "invalid media link"}), 403
    return None


@media_bp.route("/api/media/<file_id>", methods=["GET"])
def fetch_media(file_id: str):
    """Stream a stored file.

    Deliberately unauthenticated: these URLs are embedded in ``<img>`` and
    ``<audio>`` tags that cannot carry an Authorization header, and the
    identifiers are unguessable random hex.
    """
    rejection = _ticket_rejection(file_id)
    if rejection is not None:
        return rejection

    path = _resolve_stored_path(file_id)
    if path is None:
        return jsonify({"error": "file not found"}), 404

    content_type, _ = mimetypes.guess_type(path)
    # mimetypes is seeded from the host OS, so a thin container can fail to
    # recognise .mp4 and hand back octet-stream, which a <video> element
    # refuses to play. The extension came from ALLOWED_TYPES on upload, so
    # that table is the authoritative answer.
    if content_type is None:
        extension = os.path.splitext(path)[1].lower()
        content_type = EXTENSION_TYPES.get(extension)

    response = send_file(
        path,
        mimetype=content_type or "application/octet-stream",
        conditional=True,
    )
    # Content is immutable once written, so it can be cached hard.
    response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
    # Lets a player seek without refetching from byte zero.
    response.headers["Accept-Ranges"] = "bytes"
    return response
