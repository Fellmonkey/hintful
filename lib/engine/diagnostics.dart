import 'package:flutter/foundation.dart';

/// Reasons why a tour step was not shown.
///
/// A single typed enum for diagnostics instead of raw strings: testable, and
/// an event bus can reuse the same reason values without changing the
/// contract.
enum HintSkipReason {
  /// The target was not registered by the time the step was reached.
  targetNotRendered,

  /// Wait-for-target: the target did not appear within the configured timeout.
  timeout,

  /// targetId is unknown to the registry and no close candidates exist
  /// (likely a typo).
  unknownTarget,

  /// The target was mounted but vanished during an active step.
  targetUnmountedDuringStep,

  /// The user skipped the tour.
  userSkipped;

  /// Kebab-case reason name for one-line diagnostics and test mapping.
  String get label => switch (this) {
        HintSkipReason.targetNotRendered => 'target-not-rendered',
        HintSkipReason.timeout => 'timeout',
        HintSkipReason.unknownTarget => 'unknown-target',
        HintSkipReason.targetUnmountedDuringStep =>
          'target-unmounted-during-step',
        HintSkipReason.userSkipped => 'user-skipped',
      };
}

/// Handler for "why didn't it show" diagnostics.
///
/// The controller writes every failed show attempt here. Other subsystems can
/// register additional handlers implementing the same interface — the
/// contract stays unchanged and the engine never learns about them.
abstract class HintDiagnosticsHandler {
  /// Step [stepIndex] of tour [tourId] for target [targetId] was not shown
  /// for [reason]; [detail] carries reason context (timeout, message).
  void onHintSkipped(
    String tourId,
    int stepIndex,
    String targetId,
    HintSkipReason reason,
    String detail,
  );
}

/// A single diagnostics line fit for logging.
///
/// Format: `[hintful] statsIntro step 2 not shown: target-not-rendered
/// (target 'statsPeriodSelector') — detail`
String formatHintSkipped(
  String tourId,
  int stepIndex,
  String targetId,
  HintSkipReason reason,
  String detail,
) {
  return "[hintful] $tourId step ${stepIndex + 1} not shown: ${reason.label}"
      " (target '$targetId') — $detail";
}

/// Default handler: prints the formatted line via [debugPrint].
///
/// Who wires this handler is policy (the controller only attaches it in
/// debug builds, so release cost is zero).
class DebugPrintDiagnostics implements HintDiagnosticsHandler {
  const DebugPrintDiagnostics();

  @override
  void onHintSkipped(
    String tourId,
    int stepIndex,
    String targetId,
    HintSkipReason reason,
    String detail,
  ) {
    debugPrint(formatHintSkipped(tourId, stepIndex, targetId, reason, detail));
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

/// Closest candidate for [typo] among [known], or null if none are close.
String? findClosestTargetId(
  String typo,
  Set<String> known, {
  int maxDistance = 2,
}) {
  final candidates = closestTargetIds(typo, known, maxDistance: maxDistance);
  return candidates.isEmpty ? null : candidates.first;
}
