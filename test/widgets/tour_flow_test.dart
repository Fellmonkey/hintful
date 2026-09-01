import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/tooltip_tail.dart';
import 'package:hintful/hintful.dart';

import '../helpers/tour_harness.dart';

/// Full-flow tests on a real engine: `HintTarget` → controller →
/// `HintOverlayEngine` → scrim/tooltip. The harness provides the scene; the
/// tests check behavior, not wiring.
void main() {
  group('tour_flow', () {
    testWidgets('mount → wait → active → finish; zero idle cost',
        (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = HintTour(
        id: 'flow',
        steps: [
          HintStep(
              targetId: 'stats', title: 'Statistics', description: 'Step 1'),
          HintStep(
              targetId: 'records', title: 'Records', description: 'Step 2'),
        ],
      );
      await h.pump(tester);

      // Idle before start: zero engine widgets in the tree.
      h.expectIdleClean();
      expect(h.controller.currentState, isA<HintIdle>());

      // mount: step 1 is mounted → active right away (target wiring).
      await h.start(tester, tour);
      expect(
        h.controller.currentState,
        HintActive(tour: tour, stepIndex: 0),
      );
      expect(find.text('Statistics'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // wait: step 2 is not mounted → waiting (scrim without a hole).
      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);
      expect(
        h.controller.currentState,
        HintWaiting(tour: tour, stepIndex: 1),
      );
      expect(find.text('Preparing…'), findsOneWidget);
      expect(find.text('Records'), findsNothing);

      // active: the target appearing activates the step (wait-for-target).
      await h.reveal(tester, HarnessTarget('records', top: 200));
      await TourHarness.settle(tester);
      expect(
        h.controller.currentState,
        HintActive(tour: tour, stepIndex: 1),
      );
      expect(find.text('Records'), findsOneWidget);
      expect(find.text('Preparing…'), findsNothing);

      // finish: the last step → "Done", the overlay is removed.
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(h.controller.currentState, isA<HintIdle>());
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
      final tour = HintTour(
        id: 'scroll',
        steps: [HintStep(targetId: 'stats', title: 'Statistics')],
      );
      await h.pump(tester);
      await h.start(tester, tour);
      expect(h.controller.currentState, HintActive(tour: tour, stepIndex: 0));

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
      final tour = HintTour(
        id: 'flow',
        steps: [
          HintStep(targetId: 'stats', title: 'Statistics'),
          HintStep(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);
      expect(find.text('Next'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);

      expect(
        h.controller.currentState,
        HintWaiting(tour: tour, stepIndex: 1),
        reason: 'the next step (not an abort/skip)',
      );
      // The test ends in waiting: the waitTimeout timer is still pending at
      // the invariant check (before teardown) — release in the body.
      h.disposeNow();
    });
    testWidgets('Back button: next → Back returns to the previous step',
        (tester) async {
      final h = TourHarness(targets: [
        HarnessTarget('stats'),
        HarnessTarget('records', top: 200),
      ]);
      final tour = HintTour(
        id: 'flow',
        steps: [
          HintStep(targetId: 'stats', title: 'Statistics'),
          HintStep(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);
      expect(h.controller.currentState, HintActive(tour: tour, stepIndex: 0));

      // No Back on the first step.
      expect(find.text('Back'), findsNothing);

      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);
      expect(
        h.controller.currentState,
        HintActive(tour: tour, stepIndex: 1),
      );
      expect(find.text('Back'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await TourHarness.settle(tester);
      expect(h.controller.currentState, HintActive(tour: tour, stepIndex: 0));
      expect(find.text('Statistics'), findsOneWidget);
      expect(find.text('Back'), findsNothing);

      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);
      await tester.tap(find.text('Done'));
      await tester.pump();
      h.expectIdleClean();
    });

    testWidgets('tap on the overlay (past the tooltip) = next', (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = HintTour(
        id: 'flow',
        steps: [
          HintStep(targetId: 'stats', title: 'Statistics'),
          HintStep(targetId: 'records', title: 'Records'),
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
        HintWaiting(tour: tour, stepIndex: 1),
      );
      h.disposeNow(); // waiting holds a timer — release in the body
    });

    testWidgets('scroll: auto-flip re-picks the side (above → below)',
        (tester) async {
      final h = TourHarness(
        // offset 0: target at 300..380 — more space above (300) than below
        // (600-380=220) → the tooltip starts above.
        targets: [HarnessTarget('stats', top: 300, height: 80)],
        scrollable: true,
      );
      final tour = HintTour(
        id: 'flip',
        steps: [HintStep(targetId: 'stats', title: 'Statistics')],
      );
      await h.pump(tester);
      await h.start(tester, tour);

      final targetBefore = tester.getRect(find.text('stats'));
      final tipBefore = tester.getRect(find.text('Statistics'));
      expect(tipBefore.bottom, lessThan(targetBefore.top),
          reason: 'auto: more free space above → the tooltip above');

      // The target moves up; now the space below (420) beats above (100) →
      // placement is recomputed and the tooltip flips below.
      h.scrollController.jumpTo(200);
      await TourHarness.settle(tester);

      final targetAfter = tester.getRect(find.text('stats'));
      final tipAfter = tester.getRect(find.text('Statistics'));
      expect(targetAfter.top, closeTo(targetBefore.top - 200, 1.0));
      expect(tipAfter.top, greaterThan(targetAfter.bottom),
          reason: 'the side was re-picked on scroll (not stuck above)');

      await tester.tap(find.text('Done'));
      await tester.pump();
      h.expectIdleClean();
    });

    testWidgets('keep-in-safe-area: a bottom inset mirrors the tooltip above',
        (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 60);
      addTearDown(tester.view.reset);

      final h = TourHarness(
        // The target near the bottom: bottom placement fits the bare screen
        // (600) but crosses the home-indicator inset (540).
        targets: [HarnessTarget('stats', top: 380, height: 60)],
      );
      final tour = HintTour(
        id: 'safe',
        steps: [
          HintStep(
            targetId: 'stats',
            title: 'Statistics',
            description: 'A longer description so the tooltip is tall enough',
            position: TooltipPosition.bottom,
          ),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);

      final target = tester.getRect(find.text('stats'));
      final tip = tester.getRect(find.text('Statistics'));
      expect(tip.bottom, lessThan(target.top),
          reason: 'mirrored above the target instead of crossing the inset');
      expect(tip.bottom, lessThanOrEqualTo(600 - 60 + 0.5),
          reason: 'the tooltip stays inside the safe rect');

      await tester.tap(find.text('Done'));
      await tester.pump();
      h.expectIdleClean();
    });

    testWidgets('default tooltip: the tail toward the hole is on by default',
        (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = HintTour(
        id: 'tail',
        steps: [HintStep(targetId: 'stats', title: 'Statistics')],
      );
      await h.pump(tester);
      await h.start(tester, tour);

      final tailFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TooltipTailPainter,
      );
      expect(tailFinder, findsOneWidget,
          reason: 'showTail defaults to true — the arrow is drawn');

      await tester.tap(find.text('Done'));
      await tester.pump();
      h.expectIdleClean();
    });

    testWidgets('showTail: false — the default tooltip has no tail',
        (tester) async {
      final h = TourHarness(
        targets: [HarnessTarget('stats')],
        themeExtensions: [
          HintTheme.minimal(ColorScheme.fromSeed(seedColor: Colors.teal))
              .copyWith(showTail: false),
        ],
      );
      final tour = HintTour(
        id: 'tail-off',
        steps: [HintStep(targetId: 'stats', title: 'Statistics')],
      );
      await h.pump(tester);
      await h.start(tester, tour);

      expect(find.text('Statistics'), findsOneWidget,
          reason: 'the tooltip itself is still there');
      final tailFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TooltipTailPainter,
      );
      expect(tailFinder, findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pump();
      h.expectIdleClean();
    });

    testWidgets('reduce-motion: the tour runs instant under the system setting',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      // The engine's reduce-motion contract: with the OS setting on, every
      // transition is instant (zero animation) — the flow below must not
      // need extra frames or timers beyond the immediate rebuilds.
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = HintTour(
        id: 'rm',
        steps: [
          HintStep(targetId: 'stats', title: 'Statistics'),
          HintStep(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);
      expect(h.controller.currentState, HintActive(tour: tour, stepIndex: 0));
      expect(find.text('Statistics'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);
      expect(
        h.controller.currentState,
        HintWaiting(tour: tour, stepIndex: 1),
      );
      h.disposeNow(); // waiting holds a timer — release in the body
    });

    testWidgets('text scale 2.0: the tooltip still fits on screen',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // A long description: at 2× scale it wraps into many lines — without
      // the height cap the tooltip would overflow the screen.
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = HintTour(
        id: 'scale',
        steps: [
          HintStep(
            targetId: 'stats',
            title: 'Statistics',
            description: 'A deliberately long description that wraps into '
                    'many lines at double the text scale, so the tooltip needs '
                    'the height cap to stay on screen instead of overflowing '
                    'past the bottom edge. ' *
                3,
          ),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);

      final tip = tester.getRect(find.byType(DefaultTooltip));
      expect(tip.top, greaterThanOrEqualTo(0),
          reason: 'the tooltip fits vertically (top)');
      expect(tip.bottom, lessThanOrEqualTo(600),
          reason: 'the tooltip fits vertically (bottom)');
      expect(tip.left, greaterThanOrEqualTo(0));
      expect(tip.right, lessThanOrEqualTo(800));

      // The content scrolls inside the tooltip — the action stays reachable.
      await tester.ensureVisible(find.text('Done'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      h.expectIdleClean();
    });

    testWidgets('focus returns to the element focused before the tour',
        (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final h = TourHarness(
        targets: [HarnessTarget('stats')],
        leading: Focus(
          focusNode: focusNode,
          child: const SizedBox(
            width: 100,
            height: 40,
            child: Text('pre-tour element'),
          ),
        ),
      );
      final tour = HintTour(
        id: 'focus',
        steps: [HintStep(targetId: 'stats', title: 'Statistics')],
      );
      await h.pump(tester);

      // Focus the pre-tour element.
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await h.start(tester, tour);
      // The tour owns the keyboard while active — focus moved to its scope.
      expect(focusNode.hasFocus, isFalse);
      expect(h.controller.currentState, HintActive(tour: tour, stepIndex: 0));

      await tester.tap(find.text('Done'));
      await tester.pump();
      h.expectIdleClean();
      // Focus is back where it was before the tour.
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('Escape = skip: userSkipped abort through a real overlay',
        (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = HintTour(
        id: 'flow',
        steps: [
          HintStep(targetId: 'stats', title: 'Statistics'),
          HintStep(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);
      expect(h.controller.currentState, HintActive(tour: tour, stepIndex: 0));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(h.controller.currentState, isA<HintIdle>());
      h.expectIdleClean();
      final diag = h.diagnostics as DiagnosticsRecorder;
      expect(diag.events.single.reason, HintSkipReason.userSkipped);
      expect(diag.events.single.stepIndex, 0);
      expect(diag.events.single.targetId, 'stats');
    });

    testWidgets('wait-for-target timeout: abort + diagnostics', (tester) async {
      final h = TourHarness(targets: [HarnessTarget('stats')]);
      final tour = HintTour(
        id: 'flow',
        steps: [
          HintStep(targetId: 'stats', title: 'Statistics'),
          HintStep(targetId: 'records', title: 'Records'),
        ],
      );
      await h.pump(tester);
      await h.start(tester, tour);

      // Step 2 never appears — the 3s timeout gives a diagnosis.
      await tester.tap(find.text('Next'));
      await TourHarness.settle(tester);
      expect(
        h.controller.currentState,
        HintWaiting(tour: tour, stepIndex: 1),
      );

      await tester.pump(const Duration(seconds: 4));

      expect(h.controller.currentState, isA<HintIdle>());
      h.expectIdleClean();
      final diag = h.diagnostics as DiagnosticsRecorder;
      expect(diag.events.single.reason, HintSkipReason.timeout);
      expect(diag.events.single.stepIndex, 1);
      expect(diag.events.single.targetId, 'records');
    });
  });
}
