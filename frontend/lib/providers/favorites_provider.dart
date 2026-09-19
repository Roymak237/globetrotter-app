import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

class FavoritesProvider extends ChangeNotifier {
  static const _storageKey = "favorite_destination_ids";

  Set<String> _favoriteIds = <String>{};
  bool _loaded = false;

  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);
  bool get isLoaded => _loaded;
  int get count => _favoriteIds.length;

  bool isFavorite(String destinationId) => _favoriteIds.contains(destinationId);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _favoriteIds =
        preferences.getStringList(_storageKey)?.toSet() ?? <String>{};
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggle(String destinationId) async {
    final preferences = await SharedPreferences.getInstance();
    if (_favoriteIds.contains(destinationId)) {
      _favoriteIds.remove(destinationId);
    } else {
      _favoriteIds.add(destinationId);
    }
    await preferences.setStringList(_storageKey, _favoriteIds.toList());
    notifyListeners();
  }
}
