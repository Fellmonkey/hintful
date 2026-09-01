import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

import '../helpers/tour_harness.dart';

/// Full-flow tests on a real engine: `ShowcaseTarget` → controller →
/// `TourOverlayEngine` → scrim/tooltip. The harness provides the scene; the
/// tests check behavior, not wiring.
void main() {
  group('tour_flow', () {
    testWidgets('mount → wait → active → finish; zero idle cost',
        (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = TourSpec(
        id: 'flow',
        steps: [
          StepSpec(
              targetId: 'stats', title: 'Statistics', description: 'Step 1'),
          StepSpec(
              targetId: 'records', title: 'Records', description: 'Step 2'),
        ],
      );
      await h.pump(tester);

      // Idle before start: zero engine widgets in the tree.
      h.expectIdleClean();
      expect(h.controller.currentState, isA<TourIdle>());

      // mount: step 1 is mounted → active right away (target wiring).
      await h.start(tester, tour);
      expect(
        h.controller.currentState,
        TourActive(tour: tour, stepIndex: 0),
      );
      expect(find.text('Statistics'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // wait: step 2 is not mounted → waiting (scrim without a hole).
      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);
      expect(
        h.controller.currentState,
        TourWaiting(tour: tour, stepIndex: 1),
      );
      expect(find.text('Preparing…'), findsOneWidget);
      expect(find.text('Records'), findsNothing);

      // active: the target appearing activates the step (wait-for-target).
      await h.reveal(tester, HarnessTarget('records', top: 200));
      await TourHarness.settle(tester);
      expect(
        h.controller.currentState,
        TourActive(tour: tour, stepIndex: 1),
      );
      expect(find.text('Records'), findsOneWidget);
      expect(find.text('Preparing…'), findsNothing);

      // finish: the last step → "Done", the overlay is removed.
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(h.controller.currentState, isA<TourIdle>());
      h.expectIdleClean();
    });

    testWidgets(
        'scrolling under an active tour: the tooltip follows the '
        'target', (tester) async {
      final h = TourHarness(
        // scrollable: targets in a ListView (top = offset before the target).
        targets: [HarnessTarget('stats', top: 200, height: 80)],
        scrollable: true,
      );
      final tour = TourSpec(
        id: 'scroll',
        steps: [StepSpec(targetId: 'stats', title: 'Statistics')],
      );
      await h.pump(tester);
      await h.start(tester, tour);
      expect(h.controller.currentState, TourActive(tour: tour, stepIndex: 0));

      final targetBefore = tester.getRect(find.text('stats'));
      final tipBefore = tester.getRect(find.text('Statistics'));
      expect(tipBefore.top, greaterThan(targetBefore.bottom),
          reason: 'auto-placement: the tooltip below the target');

      // The scrim blocks user drag (the tour owns the screen; scroll-through
      // is follow-up). The follow mechanics is proven by a programmatic
      // scroll (like jumpTo in position_resolver_test).
      h.scrollController.jumpTo(150);
      await TourHarness.settle(tester);

      final targetAfter = tester.getRect(find.text('stats'));
      final tipAfter = tester.getRect(find.text('Statistics'));
      // The target moved up exactly 150 — the tooltip kept its position
      // relative to it (it did not "stick" at the old spot).
      expect(targetAfter.top, closeTo(targetBefore.top - 150, 1.0));
      expect(
        tipAfter.top - targetAfter.bottom,
        closeTo(tipBefore.top - targetBefore.bottom, 1.0),
        reason: 'the tooltip rides with the target',
      );

      await tester.tap(find.text('Done'));
      await tester.pump();
      h.expectIdleClean();
    });

    testWidgets('the "Next" button — a real hit-test (not a scrim fallback)',
        (tester) async {
      // Direct proof of the hit-region fix: a tap on the button reaches the
      // button, not the overlay GestureDetector (zero warnIfMissed).
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = TourSpec(
        id: 'flow',
        steps: [
          StepSpec(targetId: 'stats', title: 'Statistics'),
          StepSpec(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);
      expect(find.text('Next'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);

      expect(
        h.controller.currentState,
        TourWaiting(tour: tour, stepIndex: 1),
        reason: 'the next step (not an abort/skip)',
      );
      // The test ends in waiting: the waitTimeout timer is still pending at
      // the invariant check (before teardown) — release in the body.
      h.disposeNow();
    });

    testWidgets('tap on the overlay (past the tooltip) = next', (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = TourSpec(
        id: 'flow',
        steps: [
          StepSpec(targetId: 'stats', title: 'Statistics'),
          StepSpec(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);

      // The tooltip is below the target (auto); (700, 560) is on the scrim,
      // outside the tooltip.
      await tester.tapAt(const Offset(700, 560));
      await TourHarness.settle(tester);

      expect(
        h.controller.currentState,
        TourWaiting(tour: tour, stepIndex: 1),
      );
      h.disposeNow(); // waiting holds a timer — release in the body
    });

    testWidgets('Escape = skip: userSkipped abort through a real overlay',
        (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = TourSpec(
        id: 'flow',
        steps: [
          StepSpec(targetId: 'stats', title: 'Statistics'),
          StepSpec(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);
      expect(h.controller.currentState, TourActive(tour: tour, stepIndex: 0));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(h.controller.currentState, isA<TourIdle>());
      h.expectIdleClean();
      final diag = h.diagnostics as DiagnosticsRecorder;
      expect(diag.events.single.reason, HintSkipReason.userSkipped);
      expect(diag.events.single.stepIndex, 0);
      expect(diag.events.single.targetId, 'stats');
    });

    testWidgets('wait-for-target timeout: abort + diagnostics', (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = TourSpec(
        id: 'flow',
        steps: [
          StepSpec(targetId: 'stats', title: 'Statistics'),
          StepSpec(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);

      // Step 2 never appears — the 3s timeout gives a diagnosis.
      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);
      expect(
        h.controller.currentState,
        TourWaiting(tour: tour, stepIndex: 1),
      );

      await tester.pump(const Duration(seconds: 4));

      expect(h.controller.currentState, isA<TourIdle>());
      h.expectIdleClean();
      final diag = h.diagnostics as DiagnosticsRecorder;
      expect(diag.events.single.reason, HintSkipReason.timeout);
      expect(diag.events.single.stepIndex, 1);
      expect(diag.events.single.targetId, 'records');
    });
  });
}
