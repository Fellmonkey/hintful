import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

import '../helpers/tour_harness.dart';

/// A step that opts into `autoScroll` activates while its target is still
/// below the fold: a `ListView` cache-band child is built, laid out and
/// registered, but never painted — so it has no compositor transform either.
///
/// The tooltip must be up from the very first frame of that step, waiting at
/// the edge the target is coming from, and ride the scroll onto it. It must
/// never be parked in a screen corner (the "top-left flash") and must never
/// blink out — the poll would previously retract it because the leader was
/// unpainted, dropping the tooltip for the whole animation.
void main() {
  /// Every frame of the step transition + the autoScroll animation, from the
  /// step-change frame on.
  Future<List<Rect?>> recordFrames(
    WidgetTester tester, {
    int frames = 30,
  }) async {
    final rects = <Rect?>[];
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final tip = find.byType(DefaultTooltip);
      rects.add(tip.evaluate().isEmpty ? null : tester.getRect(tip));
    }
    return rects;
  }

  testWidgets('off-screen target: the tooltip waits at the edge and rides '
      'the page into place', (tester) async {
    final h = TourHarness(
      scrollable: true,
      targets: [
        const HarnessTarget('stats', top: 0, height: 60),
        // ~100 px below the fold, inside the cache extent (600 + 250).
        const HarnessTarget('records', top: 640, height: 60),
      ],
    );
    final tour = HintTour(
      id: 'autoScroll',
      steps: [
        const HintStep(targetId: 'stats', title: 'Statistics'),
        const HintStep(targetId: 'records', title: 'Records', autoScroll: true),
      ],
    );
    await h.pump(tester);
    await h.start(tester, tour);

    final screen = tester.getRect(find.byType(Scaffold));
    Rect target() => tester.getRect(
        find.byWidgetPredicate((w) => w is HintTarget && w.id == 'records'));

    h.controller.next();
    final frames = await recordFrames(tester);

    expect(frames.first, isNotNull,
        reason: 'the tooltip is up on the first frame of the off-screen step '
            '— autoScroll brings the target to it, not the other way round');
    expect(frames.where((r) => r == null), isEmpty,
        reason: 'no blink: nothing retracts the tooltip while the scroll is '
            'still running');

    for (final rect in frames) {
      final r = rect!;
      expect(r.topLeft, isNot(const Offset(8, 8)),
          reason: 'never parked in the safe-rect corner');
      expect(r.left, greaterThanOrEqualTo(screen.left - 0.5));
      expect(r.right, lessThanOrEqualTo(screen.right + 0.5));
      expect(r.top, greaterThanOrEqualTo(screen.top - 0.5));
      expect(r.bottom, lessThanOrEqualTo(screen.bottom + 0.5));
    }

    // While the target is still below the fold the tooltip is pinned to the
    // bottom edge — the direction the target is coming from. (The list cannot
    // scroll it fully in: maxScrollExtent runs out.)
    final waiting = frames.first!;
    expect(waiting.bottom, closeTo(screen.bottom, 1),
        reason: 'waiting at the edge the target comes from');

    // At rest the tooltip sits right above the target, gap included.
    final settled = frames.last!;
    final hole = target();
    expect(settled.overlaps(hole), isFalse);
    expect(hole.top - settled.bottom, closeTo(12, 1),
        reason: 'settled above the target with the placement gap');

    h.disposeNow();
  });
}
