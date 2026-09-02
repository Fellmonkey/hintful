import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/hintful.dart';

/// Pumps frames until [finder] matches, or [maxFrames] are exhausted.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 30,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump();
  }
  fail('not found within $maxFrames frames: $finder');
}

/// Number of engine-owned widgets currently mounted in the tree: the
/// default tooltip + the scrim (identified by its painter). 0 when no tour
/// runs, deterministic per active step.
int engineNodes() {
  final tooltips = find.byType(DefaultTooltip).evaluate().length;
  final scrims = find
      .byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ScrimHolePainter,
      )
      .evaluate()
      .length;
  return tooltips + scrims;
}
