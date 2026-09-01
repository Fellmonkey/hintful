import 'dart:math' as math;

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
/// The interface is abstract and storage-agnostic — the engine core knows
/// only this contract, so a server can substitute its own
/// implementation. The zero-dependency default ships in the core
/// ([InMemoryHintStore]); persistent implementations (e.g. backed by
/// `shared_preferences`) live OUTSIDE the core package to keep it
/// dependency-free — see the example app for one.
///
/// Whether/when to show is policy — it becomes the Hub layer in phase 2; on
/// stage 1 this is the library service plus the integration pattern
/// (`shouldShow` before start, `markShown` on exit).
abstract class HintStore {
  /// Whether the hint should show (see class doc). [minVersion] — the app
  /// version the hint targets; null — "show once ever".
  bool shouldShow(String key, {String? minVersion});

  /// Record that the hint was shown at app [version].
  void markShown(String key, String version);

  /// Forget everything. A debug/dev tool — the production "re-show" is a
  /// version bump, but a hard clear is handy in debug builds and tests.
  void clear();
}

/// Compare dotted versions (`"2.3.0"` vs `"2.10.0"`) segment-wise,
/// numerically; missing segments count as `"0"` (`"2.3"` == `"2.3.0"`);
/// non-numeric segments (build labels etc.) compare lexically — plain
/// semver-prerelease ordering (`2.0.0-dev` < `2.0.0`) is intentionally out
/// of scope. Returns negative/zero/positive.
int compareVersions(String a, String b) {
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
/// documentation of the version rules.
class InMemoryHintStore implements HintStore {
  final Map<String, String> _shown = {};

  @override
  bool shouldShow(String key, {String? minVersion}) {
    final last = _shown[key];
    if (last == null) return true;
    if (minVersion == null) return false;
    return compareVersions(last, minVersion) < 0;
  }

  @override
  void markShown(String key, String version) => _shown[key] = version;

  @override
  void clear() => _shown.clear();
}
