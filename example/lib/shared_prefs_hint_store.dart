import 'package:hintful/hintful.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's persistent [HintStore] — the [CallbackHintStore] path over
/// `shared_preferences`.
class SharedPrefsHintStore implements HintStore {
  /// Reads/writes `hintful.<key>` in [prefs]; the version rule comes from
  /// [HintStore.shouldShowVersion].
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
