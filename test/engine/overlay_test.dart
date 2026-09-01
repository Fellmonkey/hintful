import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/machine.dart';
import 'package:hintful/engine/overlay/overlay_engine.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/engine/registry.dart';
import 'package:hintful/engine/specs.dart';

/// The scrim layer in both modes — a CustomPaint with ScrimHolePainter.
final Finder _scrimFinder = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is ScrimHolePainter,
);

class _FakeInput implements TourActions {
  int nextCalls = 0;
  int skipCalls = 0;
  int finishCalls = 0;

  @override
  void next() => nextCalls++;

  @override
  void skip() => skipCalls++;

  @override
  void finish() => finishCalls++;
}

TourSpec _tour(String targetId) => TourSpec(
      id: 't',
      steps: [
        StepSpec(
            targetId: targetId, title: 'Title', description: 'Description'),
      ],
    );

/// The scene as in an app: the target (leader) + the root Overlay into which
/// the engine inserts its entry.
Widget _harness({
  required LayerLink link,
  required GlobalKey<OverlayState> overlayKey,
  double top = 40,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 20,
            top: top,
            child: CompositedTransformTarget(
              link: link,
              child: Container(
                width: 120,
                height: 60,
                color: Colors.blue,
              ),
            ),
          ),
          Positioned.fill(
            child: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(builder: (_) => const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('TourOverlayEngine', () {
    testWidgets('active: scrim hole + tooltip in the follower; tap = next',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = TargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry
          .register(TargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = TourOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      final tour = _tour('stats');

      engine.update(TourActive(tour: tour, stepIndex: 0));
      await tester.pump(); // entry mount: frame 1 — scrim only (the position
      // snapshot happens post-frame); the tooltip does not mount until an
      // authoritative position exists (otherwise the first frame would place
      // it by a zero transform).
      await tester.pump(); // snapshot → tooltip at the right place.

      // The scrim layer and the tooltip are mounted, both inside the follower.
      expect(_scrimFinder, findsOneWidget);
      expect(find.byType(CompositedTransformFollower), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);

      // Tap on the overlay (past the target) = next.
      await tester.tapAt(const Offset(400, 300));
      expect(input.nextCalls, 1);
    });

    testWidgets('active: Escape = skip, Tab/Enter = next', (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = TargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry
          .register(TargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = TourOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      engine.update(TourActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(input.skipCalls, 1);
      expect(input.nextCalls, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(input.nextCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(input.nextCalls, 2);
    });

    testWidgets(
        'waiting: full scrim without a hole (no target yet), no follower',
        (tester) async {
      final overlayKey = GlobalKey<OverlayState>();
      final registry = TargetRegistry(); // empty — the target is deferred
      final input = _FakeInput();

      await tester.pumpWidget(_harness(
        link: LayerLink(),
        overlayKey: overlayKey,
      ));

      final engine = TourOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState, // explicit overlay: no mounted
        // targets to capture from (a fully deferred scenario).
      );
      addTearDown(engine.dispose);
      final tour = _tour('deferredTarget');

      engine.update(TourWaiting(tour: tour, stepIndex: 0));
      await tester.pump();

      expect(_scrimFinder, findsOneWidget);
      expect(find.text('Preparing…'), findsOneWidget);
      expect(find.byType(CompositedTransformFollower), findsNothing);
      // The scrim paints a full CustomPaint layer (without a hole).
      expect(_scrimFinder, findsOneWidget);
    });

    testWidgets('idle removes the overlay: zero engine widgets in the tree',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = TargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry
          .register(TargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = TourOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      final tour = _tour('stats');

      engine.update(TourActive(tour: tour, stepIndex: 0));
      await tester.pump();
      expect(_scrimFinder, findsOneWidget);

      engine.update(const TourIdle());
      await tester.pump();

      expect(_scrimFinder, findsNothing);
      expect(find.byType(CompositedTransformFollower), findsNothing);
      expect(find.text('Title'), findsNothing);
      engine.dispose();
    });

    testWidgets('dispose removes the entry while the tour is still active',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = TargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry
          .register(TargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = TourOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      final tour = _tour('stats');
      engine.update(TourActive(tour: tour, stepIndex: 0));
      await tester.pump();
      expect(_scrimFinder, findsOneWidget);

      engine.dispose();
      await tester.pump();

      expect(_scrimFinder, findsNothing);
      // update after dispose — a silent no-op.
      engine.update(TourActive(tour: tour, stepIndex: 0));
      await tester.pump();
      expect(_scrimFinder, findsNothing);
    });

    testWidgets('target at the bottom edge: the tooltip auto-flips above',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = TargetRegistry();
      final input = _FakeInput();

      // Target 120x60 at y=480: below it stays 600-540=60px — less than the
      // tooltip height (~110px), the auto-flip must place it above.
      await tester.pumpWidget(
        _harness(link: link, overlayKey: overlayKey, top: 480),
      );
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry
          .register(TargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = TourOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      engine.update(TourActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump(); // entry mount: follower transform is still empty
      await tester.pump(); // post-frame snapshot → correct placement

      final targetRect = tester.getRect(find.byType(CompositedTransformTarget));
      final tooltipRect = tester.getRect(find.text('Title'));
      // The tooltip is strictly above the target and fully on-screen.
      expect(tooltipRect.bottom, lessThan(targetRect.top));
      expect(tooltipRect.top, greaterThanOrEqualTo(0));
      expect(tooltipRect.bottom, lessThanOrEqualTo(600));
    });

    testWidgets('tooltipBuilder receives StepTooltipContext (index/count)',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = TargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry
          .register(TargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = TourOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);

      final tour = TourSpec(
        id: 't',
        steps: [
          StepSpec(
            targetId: 'stats',
            tooltipBuilder: (context, step, ctx) => Text(
              'step ${ctx.stepIndex + 1} of ${ctx.totalSteps}'
              '${ctx.isLast ? " (last)" : ""}',
            ),
          ),
        ],
      );

      engine.update(TourActive(tour: tour, stepIndex: 0));
      await tester.pump(); // frame 1: scrim (snapshot post-frame)
      await tester.pump(); // tooltip of the custom builder

      expect(find.text('step 1 of 1 (last)'), findsOneWidget);
    });

    testWidgets(
        'without an overlay and without targets — unavailable '
        'diagnostics', (tester) async {
      final registry = TargetRegistry();
      final input = _FakeInput();
      final engine = TourOverlayEngine(
        registry: registry,
        input: input,
        overlay: null,
      );
      addTearDown(engine.dispose);
      final tour = _tour('deferredTarget');

      engine.update(TourWaiting(tour: tour, stepIndex: 0));
      // Nothing crashed: no entry is created, the engine stays quiet
      // (diagnostics are the controller's job via the host).
      expect(find.byType(OverlayEntry), findsNothing);
    });
  });
}
