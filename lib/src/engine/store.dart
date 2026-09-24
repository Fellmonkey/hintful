import 'dart:math' as math;

/// When a show-once path records the shown-state — one policy knob for
/// [HintController.startOnce] and `showHintTourOffer`.
///
/// Closed in 1.x: no new values before 2.0.
enum HintMarkPolicy {
  /// Mark when the tour finishes normally (Done / last step). Skip, timeout
  /// and abort do **not** mark — the tour may show again (the default).
  onFinish,

  /// Mark on any exit after the tour started: finish, skip or timeout all
  /// count as "the user has seen it". Replaces a hand-rolled
  /// `state.addListener` + `markShown` on idle.
  onAnyExit,

  /// Never mark automatically — the app owns the shown-state entirely
  /// (gate with `shouldShow` / record with `markShown` itself).
  manual,
}

/// Versioned-hints store: `{hintKey: lastShownAppVersion}`.
///
/// The "should I show" question, answered as data: a hint shows once per app
/// version, not once ever. [HintStore.markShown] records the app version at
/// which the hint was shown; [HintStore.shouldShow] with a `minVersion` (the
/// version the hint targets — "new in 2.3.0") returns true when the hint was
/// never shown or was last shown in a version OLDER than `minVersion`. A
/// version bump re-shows the hint; a re-run in the same version does not.
///
/// The semantic of "show all tours again" is bumping the version, not wiping
/// flags — the old `resetAll()`-style flag reset is replaced by
/// `{key: lastShownVersion}` bookkeeping.
///
/// **Contract for the whole 1.x line (a conscious 1.0 decision):** the three
/// abstract members below are the complete interface — apps that
/// `implements HintStore` will not break on a 1.x upgrade. Growth happens
/// through Dart extension methods on [HintStore] (non-breaking for every
/// implementor), never through a new abstract member; a fourth abstract
/// member is a 2.0 change.
///
/// The interface is abstract and storage-agnostic — the engine core knows
/// only this contract, so a server can substitute its own
/// implementation. The zero-dependency default ships in the core
/// ([InMemoryHintStore]); the fastest persistent implementation is
/// [CallbackHintStore] over your own `read`/`write` (SharedPreferences,
/// a key-value file, secure storage — ~3 lines, no subclassing). Heavier
/// needs (namespacing, migration) are a plain `implements HintStore`;
/// either way the storage stays OUTSIDE the core package to keep it
/// dependency-free — see the example app.
///
/// Typical use: set it once on the controller (`HintController(store: ...)`)
/// and call `startOnce` with no per-call store — or the manual gate
/// `shouldShow` before start + `markShown` on the exit you choose.
///
/// Version ordering lives on the class: [HintStore.compareVersions] is the
/// shared dotted-version comparator (reusable by app-side stores).
abstract class HintStore {
  /// Compare dotted versions (`"2.3.0"` vs `"2.10.0"`) segment-wise,
  /// numerically; missing segments count as `"0"` (`"2.3"` == `"2.3.0"`);
  /// non-numeric segments (build labels etc.) compare lexically — plain
  /// semver-prerelease ordering (`2.0.0-dev` < `2.0.0`) is intentionally out
  /// of scope. Returns negative/zero/positive.
  ///
  /// Shared by [shouldShow] implementations; kept public so app-side
  /// stores can reuse it.
  static int compareVersions(String a, String b) => _compareVersions(a, b);

  /// Whether the hint should show (see class doc). [minVersion] — the app
  /// version the hint targets; null — "show once ever".
  bool shouldShow(String key, {String? minVersion});

  /// Record that the hint was shown at app [version].
  void markShown(String key, String version);

  /// Forget everything. A debug/dev tool — the production "re-show" is a
  /// version bump, but a hard clear is handy in debug builds and tests.
  void clear();
}

int _compareVersions(String a, String b) {
  final pa = a.split('.');
  final pb = b.split('.');
  final n = math.max(pa.length, pb.length);
  for (var i = 0; i < n; i++) {
    final sa = i < pa.length ? pa[i] : '0';
    final sb = i < pb.length ? pb[i] : '0';
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    final cmp = na != null && nb != null ? na.compareTo(nb) : sa.compareTo(sb);
    if (cmp != 0) return cmp;
  }
  return 0;
}

/// Zero-dependency default: everything held in memory.
///
/// Also the reference implementation — the same semantics any persistent
/// store must implement, so it doubles as the fake in widget tests and as
/// documentation of the version rules. Not persistent: the shown-state dies
/// with the process — for a product onboarding flow use [CallbackHintStore]
/// over your app's storage.
class InMemoryHintStore implements HintStore {
  final Map<String, String> _shown = {};

  @override
  bool shouldShow(String key, {String? minVersion}) {
    final last = _shown[key];
    if (last == null) return true;
    if (minVersion == null) return false;
    return _compareVersions(last, minVersion) < 0;
  }

  @override
  void markShown(String key, String version) => _shown[key] = version;

  @override
  void clear() => _shown.clear();
}

/// A [HintStore] over plain `read`/`write` callbacks — the three-line path
/// to a persistent store, no subclass and no `implements` ceremony:
///
/// ```dart
/// final store = CallbackHintStore(
///   read: (key) => prefs.getString('hintful.$key'),
///   write: (key, version) => prefs.setString('hintful.$key', version),
///   clear: () { /* optional: wipe the namespaced keys */ },
/// );
/// final controller = HintController(store: store);
/// ```
///
/// Same version semantics as [InMemoryHintStore] (this is the shipping
/// implementation of those rules over your storage). [clear] is the
/// debug/dev tool of the [HintStore] contract — with [onClear] omitted it
/// is a no-op (a key-value store usually cannot enumerate its keys).
class CallbackHintStore implements HintStore {
  /// Wires the store over [read] (null — never shown), [write] and the
  /// optional [onClear] used by [clear].
  CallbackHintStore({
    required String? Function(String key) read,
    required void Function(String key, String version) write,
    void Function()? onClear,
  })  : _read = read,
        _write = write,
        _onClear = onClear;

  final String? Function(String key) _read;
  final void Function(String key, String version) _write;
  final void Function()? _onClear;

  @override
  bool shouldShow(String key, {String? minVersion}) {
    final last = _read(key);
    if (last == null) return true;
    if (minVersion == null) return false;
    return HintStore.compareVersions(last, minVersion) < 0;
  }

  @override
  void markShown(String key, String version) => _write(key, version);

  @override
  void clear() => _onClear?.call();
}
