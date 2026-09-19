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
POST /api/media            Upload a file, returns its public URL
GET  /api/media/<file_id>  Stream a stored file back
"""
import datetime
import mimetypes
import os
import uuid

from flask import Blueprint, jsonify, request, send_file

from app.auth import get_current_user
from app.models import MEDIA_DIR

media_bp = Blueprint("media", __name__)

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


@media_bp.route("/api/media/<file_id>", methods=["GET"])
def fetch_media(file_id: str):
    """Stream a stored file.

    Deliberately unauthenticated: these URLs are embedded in ``<img>`` and
    ``<audio>`` tags that cannot carry an Authorization header, and the
    identifiers are unguessable random hex.
    """
    path = _resolve_stored_path(file_id)
    if path is None:
        return jsonify({"error": "file not found"}), 404

    content_type, _ = mimetypes.guess_type(path)
    response = send_file(
        path,
        mimetype=content_type or "application/octet-stream",
        conditional=True,
    )
    # Content is immutable once written, so it can be cached hard.
    response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
    return response
