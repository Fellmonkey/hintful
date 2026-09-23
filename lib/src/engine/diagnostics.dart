import 'package:flutter/foundation.dart';

/// Reasons why a tour step was not shown.
///
/// A single typed enum for diagnostics instead of raw strings: testable, and
/// an event bus can reuse the same reason values without changing the
/// contract.
///
/// **Closed for the whole 1.x line — a conscious 1.0 decision:** exhaustive
/// `switch`es over this enum in app code will not break before 2.0. A new
/// diagnostic kind (replaced, feature-flagged-out, …) is a 2.0 change with a
/// migration note, not a hidden 1.x addition. ([HintSkipEvent] fields stay
/// extensible within 1.x — new fields are optional-only; this reason set
/// does not grow with them.) For analytics that should survive the 2.0
/// addition, log [HintSkipEvent.reason]'s [label] (a stable string) and keep
/// context in [HintSkipEvent.detail] — string-keyed sinks never switch.
enum HintSkipReason {
  /// The render host could not be mounted: no `OverlayState` was reachable
  /// and no mounted target was available to capture the root overlay from.
  /// Matters for fully-deferred scenarios — pass `overlay:` to
  /// `HintController`.
  overlayUnavailable,

  /// Wait-for-target: the target did not appear within the configured timeout.
  timeout,

  /// targetId is unknown to the registry and no close candidates exist
  /// (likely a typo).
  unknownTarget,

  /// The user skipped the tour.
  userSkipped;

  /// Kebab-case reason name for one-line diagnostics and test mapping.
  String get label => switch (this) {
        HintSkipReason.overlayUnavailable => 'overlay-unavailable',
        HintSkipReason.timeout => 'timeout',
        HintSkipReason.unknownTarget => 'unknown-target',
        HintSkipReason.userSkipped => 'user-skipped',
      };
}

/// A single "step was not shown" event — the diagnostics payload.
///
/// An event object instead of positional arguments: new fields (version,
/// screen, timestamp) can be added in 1.x without breaking implementations
/// of [HintDiagnosticsHandler] — **optional fields only** (a new `required`
/// constructor parameter would break event construction in app tests).
@immutable
class HintSkipEvent {
  /// Builds an event from the skipped step's context.
  const HintSkipEvent({
    required this.tourId,
    required this.stepIndex,
    required this.targetId,
    required this.reason,
    required this.detail,
  });

  /// Tour the skipped step belongs to (`'?'` when the tour is unknown).
  final String tourId;

  /// 0-based index of the skipped step.
  final int stepIndex;

  /// Target the step was waiting on (`'?'` when unknown).
  final String targetId;

  /// Why the step was not shown.
  final HintSkipReason reason;

  /// Reason context (timeout value, closest candidates, message).
  final String detail;
}

/// Handler for "why didn't it show" diagnostics — a plain function taking
/// one [HintSkipEvent].
///
/// One handler per controller, passed as the constructor's `diagnostics:`
/// parameter; to fan out to several sinks, do it inside the one function.
/// The controller reports every failed show here: wait timeouts, typos,
/// user skips and engine-side overlay failures — the same channel, one
/// event object per failure.
///
/// ```dart
/// HintController(diagnostics: (e) => analytics.log('hint_skipped', {
///   'tour': e.tourId,
///   'step': e.stepIndex,
///   'reason': e.reason.label,
/// }));
/// ```
///
/// A function type, not a class: attaching analytics cannot break the
/// contract in 1.x (there is no method to add), and the call site needs no
/// ceremony. Debug builds **always print the same event as one line**
/// (`[hintful] …`) first, then invoke this callback when one is attached —
/// a custom handler never costs you the console diagnosis. In release the
/// callback runs alone (zero print cost) or is absent (zero cost at all).
typedef HintDiagnosticsHandler = void Function(HintSkipEvent event);

/// A single diagnostics line fit for logging.
///
/// Format: `[hintful] statsIntro step 2 not shown: overlay-unavailable
/// (target 'statsPeriodSelector') — detail`
String formatHintSkipped(HintSkipEvent event) {
  return "[hintful] ${event.tourId} step ${event.stepIndex + 1} not shown:"
      " ${event.reason.label} (target '${event.targetId}') — ${event.detail}";
}

/// Debug-build default sink: the one-line diagnosis through [debugPrint].
/// Attached automatically in debug builds (before any user callback) —
/// not part of the public barrel.
void debugPrintHintSkip(HintSkipEvent event) =>
    debugPrint(formatHintSkipped(event));

/// Levenshtein (edit) distance between [a] and [b].
///
/// Identifiers are case-sensitive; distance ≤ 2 counts as "similar" for
/// typo-candidate search. Classic single-row DP, no external dependencies.
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final rows = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    var prev = rows[0];
    rows[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final tmp = rows[j];
      rows[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
          ? prev
          : 1 + _min3(rows[j], rows[j - 1], prev);
      prev = tmp;
    }
  }
  return rows[b.length];
}

int _min3(int a, int b, int c) => a < b ? (a < c ? a : c) : (b < c ? b : c);

/// Ids from [known] similar to [typo] (distance ≤ [maxDistance]), sorted by
/// ascending distance then alphabetically; at most [limit] results.
List<String> closestTargetIds(
  String typo,
  Set<String> known, {
  int maxDistance = 2,
  int limit = 3,
}) {
  final scored = <(int, String)>[];
  for (final id in known) {
    final d = editDistance(typo, id);
    if (d <= maxDistance) scored.add((d, id));
  }
  scored.sort((x, y) {
    final byDistance = x.$1.compareTo(y.$1);
    return byDistance != 0 ? byDistance : x.$2.compareTo(y.$2);
  });
  return scored.take(limit).map((e) => e.$2).toList();
}
