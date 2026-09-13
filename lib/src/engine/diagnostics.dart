import 'package:flutter/foundation.dart';

/// Reasons why a tour step was not shown.
///
/// A single typed enum for diagnostics instead of raw strings: testable, and
/// an event bus can reuse the same reason values without changing the
/// contract.
///
/// Closed in 1.x: no new values will be added before 2.0 — exhaustive
/// `switch`es over this enum in app code are safe. ([HintSkipEvent] fields
/// stay extensible; this reason set does not grow with them.)
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
/// of [HintDiagnosticsHandler].
@immutable
class HintSkipEvent {
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

/// Handler for "why didn't it show" diagnostics.
///
/// The controller writes every failed show attempt here as a [HintSkipEvent].
/// Other subsystems can register additional handlers implementing the same
/// interface — the contract stays unchanged and the engine never learns
/// about them.
abstract class HintDiagnosticsHandler {
  /// Step [HintSkipEvent.stepIndex] of tour [HintSkipEvent.tourId] for
  /// target [HintSkipEvent.targetId] was not shown for
  /// [HintSkipEvent.reason]; [HintSkipEvent.detail] carries reason context.
  void onHintSkipped(HintSkipEvent event);
}

/// A single diagnostics line fit for logging.
///
/// Format: `[hintful] statsIntro step 2 not shown: overlay-unavailable
/// (target 'statsPeriodSelector') — detail`
String formatHintSkipped(HintSkipEvent event) {
  return "[hintful] ${event.tourId} step ${event.stepIndex + 1} not shown:"
      " ${event.reason.label} (target '${event.targetId}') — ${event.detail}";
}

/// Default handler: prints the formatted line via [debugPrint].
///
/// Who wires this handler is policy (the controller only attaches it in
/// debug builds, so release cost is zero).
class DebugPrintDiagnostics implements HintDiagnosticsHandler {
  const DebugPrintDiagnostics();

  @override
  void onHintSkipped(HintSkipEvent event) {
    debugPrint(formatHintSkipped(event));
  }
}

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
