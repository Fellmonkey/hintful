import 'package:hintful/hintful.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's persistent [HintStore] — the `CallbackHintStore` path over
/// `shared_preferences`, kept app-side on purpose: the library core stays
/// dependency-free ("dart:ui + widgets only") and the example must not
/// depend on a *published* package to build (fresh clone / CI: no
/// `hintful_prefs 1.0.0` exists yet when this repo's 1.0.0 lands).
///
/// For a ready-made store with the same wiring (namespaced keys and a
/// `clear()` dev tool) use the `hintful_prefs` companion package — this is
/// the zero-dependency version of it, not a competitor:
/// <https://pub.dev/packages/hintful_prefs>
///
/// The store is wired app-wide once via `Hintful.configure(store: ...)` in
/// `main.dart` — `startOnce` / `showHintTourOffer` read it with no per-call
/// `store:`.
class SharedPrefsHintStore implements HintStore {
  /// Reads/writes `hintful.<key>` in [prefs]. The version rule itself is
  /// the shared [HintStore.shouldShowVersion] inside [CallbackHintStore] —
  /// no second copy of that gate lives here.
  SharedPrefsHintStore(SharedPreferences prefs) : _prefs = prefs {
    _delegate = CallbackHintStore(
      read: (key) => _prefs.getString('$_prefix$key'),
      write: (key, version) => _prefs.setString('$_prefix$key', version),
    );
  }

  static const _prefix = 'hintful.';

  final SharedPreferences _prefs;
  late final CallbackHintStore _delegate;

  @override
  bool shouldShow(String key, {String? minVersion}) =>
      _delegate.shouldShow(key, minVersion: minVersion);

  @override
  void markShown(String key, String version) =>
      _delegate.markShown(key, version);

  /// Forget every recorded shown-state — the demo's "Reset store" button.
  /// A debug/dev tool, deliberately not part of the [HintStore] contract
  /// (the production re-show is a version bump).
  void clear() {
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith(_prefix)) _prefs.remove(key);
    }
  }
}
