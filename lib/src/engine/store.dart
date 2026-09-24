import 'dart:math' as math;

/// When a show-once path records the shown-state — one policy knob for
/// [HintController.startOnce] and `showHintTourOffer`.
///
/// Closed in 1.x: no new values before 2.0.
enum HintMarkPolicy {
  /// Mark when the tour finishes normally (Done / last step). Skip, timeout
  /// and abort do **not** mark — the tour may show again. Use this when only
  /// a completed tour counts as "seen".
  onFinish,

  /// Mark on any exit after the tour started: finish, skip or timeout all
  /// count as "the user has seen it" (the default). Replaces a hand-rolled
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
/// **Contract for the whole 1.x line (a conscious 1.0 decision):** the two
/// abstract members below are the complete interface — apps that
/// `implements HintStore` will not break on a 1.x upgrade. Growth happens
/// through Dart extension methods on [HintStore] (non-breaking for every
/// implementor), never through a new abstract member; a third abstract
/// member is a 2.0 change. (Debug/dev clearing is not part of the contract —
/// a concrete store may expose its own `clear()`; the shipped
/// `hintful_prefs` package does.)
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
/// Typical use: configure it once at startup (`Hintful.configure(store: ...)`)
/// and call `startOnce` with no per-call store — or the manual gate
/// `shouldShow` before start + `markShown` on the exit you choose.
abstract class HintStore {
  /// Whether the hint should show (see class doc). [minVersion] — the app
  /// version the hint targets; null — "show once ever".
  bool shouldShow(String key, {String? minVersion});

  /// Record that the hint was shown at app [version].
  void markShown(String key, String version);
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

  /// Forget everything — a debug/dev tool, not part of the [HintStore]
  /// contract (the production "re-show" is a version bump). Concrete
  /// stores expose their own; the shipped `hintful_prefs` store does.
  void clear() => _shown.clear();
}

/// A [HintStore] over plain `read`/`write` callbacks — the three-line path
/// to a persistent store, no subclass and no `implements` ceremony:
///
/// ```dart
/// final store = CallbackHintStore(
///   read: (key) => prefs.getString('hintful.$key'),
///   write: (key, version) => prefs.setString('hintful.$key', version),
/// );
/// Hintful.configure(store: store);
/// ```
///
/// Same version semantics as [InMemoryHintStore] (this is the shipping
/// implementation of those rules over your storage). For a ready-made
/// `shared_preferences` store (plus a `clear()` dev tool) use the
/// `hintful_prefs` package.
class CallbackHintStore implements HintStore {
  /// Wires the store over [read] (null — never shown) and [write].
  CallbackHintStore({
    required String? Function(String key) read,
    required void Function(String key, String version) write,
  })  : _read = read,
        _write = write;

  final String? Function(String key) _read;
  final void Function(String key, String version) _write;

  @override
  bool shouldShow(String key, {String? minVersion}) {
    final last = _read(key);
    if (last == null) return true;
    if (minVersion == null) return false;
    return _compareVersions(last, minVersion) < 0;
  }

  @override
  void markShown(String key, String version) => _write(key, version);
}
