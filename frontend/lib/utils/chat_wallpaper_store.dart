import "package:shared_preferences/shared_preferences.dart";

/// Remembers each conversation's wallpaper on this device.
///
/// Deliberately local rather than server-side. A wallpaper is a personal
/// preference about how *you* read a room, not a property of the room, so
/// syncing it would impose one person's choice on everyone else in a group.
/// The cost is that the choice does not follow you to another device, which is
/// the same trade-off the platform messengers make.
class ChatWallpaperStore {
  /// Injectable so tests can drive the store without a platform channel.
  static Future<SharedPreferences> Function() loader =
      SharedPreferences.getInstance;

  static String _key(String roomId) => "chat_wallpaper.$roomId";

  /// The stored wallpaper id for [roomId], or null when none was chosen.
  ///
  /// Swallows storage failures. A conversation must still open when
  /// preferences are unavailable; losing a wallpaper is not worth a crash.
  static Future<String?> load(String roomId) async {
    try {
      return (await loader()).getString(_key(roomId));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String roomId, String wallpaperId) async {
    try {
      await (await loader()).setString(_key(roomId), wallpaperId);
    } catch (_) {
      // Same reasoning as load: a failed write must not break the chat.
    }
  }
}
