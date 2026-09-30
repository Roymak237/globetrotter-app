import "constants.dart";

/// Turns a stored media reference into something an image widget can load.
///
/// The backend stores avatars and chat attachments as root-relative paths such
/// as `/api/media/<id>.jpg`, because the host it is reached on differs between
/// local development, the LAN and production, and baking an origin into the
/// record would pin it to whichever one happened to write it.
///
/// That relative form is fine in a browser, which resolves it against the page
/// origin, and broken everywhere else: `Image.network` on Android, iOS and
/// desktop hands the string to `HttpClient.getUrl`, which requires an absolute
/// URL and throws on a path. An avatar that renders in Chrome can therefore
/// fail on a phone, which is exactly the kind of difference that survives
/// testing on one platform.
///
/// Returns an empty string for anything unusable so callers can fall back to
/// initials with a single `isEmpty` check rather than a try/catch.
String resolveMediaUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return "";

  final parsed = Uri.tryParse(trimmed);
  if (parsed == null) return "";

  if (parsed.hasScheme) {
    // Records predating the upload-only rule may still hold absolute URLs, so
    // these are passed through - but only for schemes that name a fetchable
    // image. `data:` and `javascript:` are refused because an avatar is shown
    // to everyone who sees the profile, which makes it an attractive place to
    // park a payload.
    return (parsed.scheme == "http" || parsed.scheme == "https") ? trimmed : "";
  }

  // A protocol-relative URL ("//host/path") is absolute in the sense that it
  // names a foreign host, and `resolve` would happily keep that host while
  // borrowing our scheme. Treat it like any other off-site reference.
  if (trimmed.startsWith("//")) return "";

  return Uri.parse(AppConstants.backendBaseUrl).resolve(trimmed).toString();
}
