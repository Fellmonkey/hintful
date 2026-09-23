import 'package:hintful/hintful.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent [HintStore] on `shared_preferences` — the three-line
/// `CallbackHintStore` pattern a product app uses (e.g. FitTracker).
///
/// It lives in the app, not in the library: the core package stays
/// dependency-free ("dart:ui + widgets only"), the app owns its storage and
/// injects the store once via `HintController(store: ...)`. Keys are
/// namespaced (`hintful.<hintKey>`) so they do not collide with the app's
/// own preferences; `onClear` wipes only that namespace (the debug/dev tool
/// of the [HintStore] contract).
HintStore sharedPrefsHintStore(SharedPreferences prefs) {
  const prefix = 'hintful.';
  return CallbackHintStore(
    read: (key) => prefs.getString(prefix + key),
    write: (key, version) => prefs.setString(prefix + key, version),
    onClear: () {
      for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
        prefs.remove(key);
      }
    },
  );
}
