import 'package:hintful/hintful.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent [HintStore] on `shared_preferences` — the pattern a product
/// app uses (e.g. FitTracker).
///
/// It lives in the app, not in the library: the core package stays
/// dependency-free ("dart:ui + widgets only"), the app owns its storage and
/// injects the store where needed. Keys are namespaced (`hintful.<hintKey>`)
/// so they do not collide with the app's own preferences.
class SharedPrefsHintStore implements HintStore {
  SharedPrefsHintStore(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'hintful.';

  @override
  bool shouldShow(String key, {String? minVersion}) {
    final last = _prefs.getString(_prefix + key);
    if (last == null) return true;
    if (minVersion == null) return false;
    return compareVersions(last, minVersion) < 0;
  }

  @override
  void markShown(String key, String version) =>
      _prefs.setString(_prefix + key, version);

  @override
  void clear() {
    for (final key in _prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      _prefs.remove(key);
    }
  }
}
