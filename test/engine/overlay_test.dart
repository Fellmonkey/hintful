import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/machine.dart';
import 'package:hintful/engine/overlay/overlay_engine.dart';
import 'package:hintful/engine/overlay/pulse_painter.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/engine/registry.dart';
import 'package:hintful/engine/specs.dart';
import 'package:hintful/engine/theme/hint_theme.dart';

/// The scrim layer in both modes — a CustomPaint with ScrimHolePainter.
final Finder _scrimFinder = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is ScrimHolePainter,
);

class _FakeInput implements HintActions {
  int nextCalls = 0;
  int previousCalls = 0;
  int skipCalls = 0;
  int finishCalls = 0;

  @override
  void next() => nextCalls++;

  @override
  void previous() => previousCalls++;

  @override
  void skip() => skipCalls++;

  @override
  void finish() => finishCalls++;
}

HintTour _tour(String targetId) => HintTour(
      id: 't',
      steps: [
        HintStep(
            targetId: targetId, title: 'Title', description: 'Description'),
      ],
    );

/// The scene as in an app: the targets (leaders) + the root Overlay into
/// which the engine inserts its entry. [extra] adds secondary targets
/// (multi-target steps); [theme] applies a custom [HintTheme].
Widget _harness({
  required LayerLink link,
  required GlobalKey<OverlayState> overlayKey,
  double top = 40,
  List<(LayerLink, double)> extra = const [],
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: theme,
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
          for (final (extraLink, extraTop) in extra)
            Positioned(
              left: 300,
              top: extraTop,
              child: CompositedTransformTarget(
                link: extraLink,
                child: Container(
                  width: 100,
                  height: 50,
                  color: Colors.red,
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
  group('HintOverlayEngine', () {
    testWidgets('active: scrim hole + tooltip in the follower; tap = next',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      final tour = _tour('stats');

      engine.update(HintActive(tour: tour, stepIndex: 0));
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
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      engine.update(HintActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(input.skipCalls, 1);
      expect(input.nextCalls, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(input.nextCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(input.nextCalls, 2);
    });

    testWidgets('active: Shift+Tab = previous, Tab = next', (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      engine.update(HintActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(input.previousCalls, 1);
      expect(input.nextCalls, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // no shift
      expect(input.nextCalls, 1);
      expect(input.previousCalls, 1);
    });

    testWidgets(
        'disableBackButton: route pop is consumed while the tour is '
        'active', (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);

      // Without the flag: the pop is not consumed.
      engine.update(HintActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump();
      expect(await tester.binding.handlePopRoute(), isFalse);

      // With the flag: the pop is consumed (returned true).
      final blocked = HintTour(
        id: 't',
        disableBackButton: true,
        steps: [
          HintStep(
              targetId: 'stats', title: 'Title', description: 'Description'),
        ],
      );
      engine.update(HintActive(tour: blocked, stepIndex: 0));
      await tester.pump();
      expect(await tester.binding.handlePopRoute(), isTrue);

      // After the tour ends (idle), the pop is not consumed any more.
      engine.update(const HintIdle());
      await tester.pump();
      expect(await tester.binding.handlePopRoute(), isFalse);
    });

    testWidgets(
        'waiting: full scrim without a hole (no target yet), no follower',
        (tester) async {
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry(); // empty — the target is deferred
      final input = _FakeInput();

      await tester.pumpWidget(_harness(
        link: LayerLink(),
        overlayKey: overlayKey,
      ));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState, // explicit overlay: no mounted
        // targets to capture from (a fully deferred scenario).
      );
      addTearDown(engine.dispose);
      final tour = _tour('deferredTarget');

      engine.update(HintWaiting(tour: tour, stepIndex: 0));
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
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      final tour = _tour('stats');

      engine.update(HintActive(tour: tour, stepIndex: 0));
      await tester.pump();
      expect(_scrimFinder, findsOneWidget);

      engine.update(const HintIdle());
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
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      final tour = _tour('stats');
      engine.update(HintActive(tour: tour, stepIndex: 0));
      await tester.pump();
      expect(_scrimFinder, findsOneWidget);

      engine.dispose();
      await tester.pump();

      expect(_scrimFinder, findsNothing);
      // update after dispose — a silent no-op.
      engine.update(HintActive(tour: tour, stepIndex: 0));
      await tester.pump();
      expect(_scrimFinder, findsNothing);
    });

    testWidgets('target at the bottom edge: the tooltip auto-flips above',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      // Target 120x60 at y=480: below it stays 600-540=60px — less than the
      // tooltip height (~110px), the auto-flip must place it above.
      await tester.pumpWidget(
        _harness(link: link, overlayKey: overlayKey, top: 480),
      );
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      engine.update(HintActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump(); // entry mount: follower transform is still empty
      await tester.pump(); // post-frame snapshot → correct placement

      final targetRect = tester.getRect(find.byType(CompositedTransformTarget));
      final tooltipRect = tester.getRect(find.text('Title'));
      // The tooltip is strictly above the target and fully on-screen.
      expect(tooltipRect.bottom, lessThan(targetRect.top));
      expect(tooltipRect.top, greaterThanOrEqualTo(0));
      expect(tooltipRect.bottom, lessThanOrEqualTo(600));
    });

    testWidgets('tooltipBuilder receives HintTooltipContext (index/count)',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);

      final tour = HintTour(
        id: 't',
        steps: [
          HintStep(
            targetId: 'stats',
            tooltipBuilder: (context, step, ctx) => Text(
              'step ${ctx.stepIndex + 1} of ${ctx.totalSteps}'
              '${ctx.isLast ? " (last)" : ""}',
            ),
          ),
        ],
      );

      engine.update(HintActive(tour: tour, stepIndex: 0));
      await tester.pump(); // frame 1: scrim (snapshot post-frame)
      await tester.pump(); // tooltip of the custom builder

      expect(find.text('step 1 of 1 (last)'), findsOneWidget);
    });

    testWidgets(
        'without an overlay and without targets — unavailable '
        'diagnostics', (tester) async {
      final registry = HintTargetRegistry();
      final input = _FakeInput();
      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: null,
      );
      addTearDown(engine.dispose);
      final tour = _tour('deferredTarget');

      engine.update(HintWaiting(tour: tour, stepIndex: 0));
      // Nothing crashed: no entry is created, the engine stays quiet
      // (diagnostics are the controller's job via the host).
      expect(find.byType(OverlayEntry), findsNothing);
    });

    testWidgets(
        'multi-target: a follower per target, one tooltip on the primary, '
        'tap on a secondary target = next', (tester) async {
      final primaryLink = LayerLink();
      final extraLink = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      // The secondary is on the same row, right of the primary: it does not
      // block the tooltip's bottom placement (the veto would otherwise
      // mirror it above — the feature working, but not this test's point).
      await tester.pumpWidget(_harness(
        link: primaryLink,
        overlayKey: overlayKey,
        extra: [(extraLink, 40)],
      ));
      final targetFinder = find.byType(CompositedTransformTarget);
      registry.register(HintTargetRegistration(
        id: 'primary',
        link: primaryLink,
        context: tester.element(targetFinder.first),
      ));
      registry.register(HintTargetRegistration(
        id: 'extra',
        link: extraLink,
        context: tester.element(targetFinder.last),
      ));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      final tour = HintTour(
        id: 't',
        steps: [
          HintStep(
            targetId: 'primary',
            moreTargets: const ['extra'],
            title: 'Title',
          ),
        ],
      );

      engine.update(HintActive(tour: tour, stepIndex: 0));
      await tester.pump();
      await tester.pump();

      // Two followers: the primary (scrim host) + the resolver-only secondary.
      expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
      expect(find.text('Title'), findsOneWidget);
      // The tooltip is anchored to the primary target.
      final primaryRect = tester.getRect(targetFinder.first);
      expect(
        tester.getRect(find.text('Title')).top,
        greaterThan(primaryRect.bottom),
      );

      // Tap on the secondary target — the target region (default next).
      await tester.tapAt(tester.getCenter(targetFinder.last));
      expect(input.nextCalls, 1);
    });

    testWidgets(
        'tap regions: onTapTarget/onTapOverlay receive the tap position',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);

      Offset? targetTap;
      Offset? overlayTap;
      final tour = HintTour(
        id: 't',
        steps: [
          HintStep(
            targetId: 'stats',
            title: 'Title',
            onTapTarget: (ctx, details) => targetTap = details.globalPosition,
            onTapOverlay: (ctx, details) => overlayTap = details.globalPosition,
          ),
        ],
      );
      engine.update(HintActive(tour: tour, stepIndex: 0));
      await tester.pump();
      await tester.pump();

      // Tap on the target itself → the target callback with its position.
      final targetCenter =
          tester.getCenter(find.byType(CompositedTransformTarget));
      await tester.tapAt(targetCenter);
      expect(targetTap, targetCenter);
      expect(overlayTap, isNull);

      // Tap on the scrim far from the target and the tooltip → the overlay
      // callback. The callbacks replaced the default "next" — no advance.
      const scrimTap = Offset(700, 550);
      await tester.tapAt(scrimTap);
      expect(overlayTap, scrimTap);
      expect(input.nextCalls, 0);
    });

    testWidgets('tapOnTarget: false disables the target region',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      final tour = HintTour(
        id: 't',
        steps: [
          HintStep(
            targetId: 'stats',
            title: 'Title',
            tapOnTarget: false,
          ),
        ],
      );
      engine.update(HintActive(tour: tour, stepIndex: 0));
      await tester.pump();
      await tester.pump();

      await tester
          .tapAt(tester.getCenter(find.byType(CompositedTransformTarget)));
      expect(input.nextCalls, 0, reason: 'the target region is disabled');
    });

    testWidgets('blur scrim: a BackdropFilter replaces the plain-dim painter',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();
      final theme = ThemeData(
        extensions: [
          HintTheme.minimal(ColorScheme.fromSeed(seedColor: Colors.teal))
              .copyWith(imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6)),
        ],
      );

      await tester.pumpWidget(
        _harness(link: link, overlayKey: overlayKey, theme: theme),
      );
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      engine.update(HintActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump();
      await tester.pump();

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(_scrimFinder, findsNothing,
          reason: 'blur mode: no plain-dim painter (the blur layer is the '
              'scrim)');
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('multi-content: a custom-builder extra slot renders',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();

      await tester.pumpWidget(_harness(link: link, overlayKey: overlayKey));
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      final tour = HintTour(
        id: 't',
        steps: [
          HintStep(
            targetId: 'stats',
            title: 'Primary',
            moreTooltips: [
              HintTooltip(
                position: TooltipPosition.right,
                tooltipBuilder: (context, step, ctx) =>
                    const Text('custom slot'),
              ),
            ],
          ),
        ],
      );
      engine.update(HintActive(tour: tour, stepIndex: 0));
      await tester.pump();
      await tester.pump();

      expect(find.text('Primary'), findsOneWidget,
          reason: 'the primary tooltip is still there');
      expect(find.text('custom slot'), findsOneWidget,
          reason: 'the builder extra renders its own content');
      expect(find.text('Done'), findsOneWidget,
          reason: 'only the primary keeps the button row (the tour has one '
              'step → Done, not Next)');
    });

    testWidgets('pulse ring renders when showPulse is on', (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();
      final theme = ThemeData(
        extensions: [
          HintTheme.minimal(ColorScheme.fromSeed(seedColor: Colors.teal))
              .copyWith(showPulse: true),
        ],
      );

      await tester.pumpWidget(
        _harness(link: link, overlayKey: overlayKey, theme: theme),
      );
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      engine.update(HintActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump();
      await tester.pump();

      final pulseFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PulsePainter,
      );
      expect(pulseFinder, findsOneWidget);
      expect(_scrimFinder, findsOneWidget,
          reason: 'non-blur mode: the plain dim is still there');
    });

    testWidgets('blur + pulse: the ring paints above the blur scrim',
        (tester) async {
      final link = LayerLink();
      final overlayKey = GlobalKey<OverlayState>();
      final registry = HintTargetRegistry();
      final input = _FakeInput();
      final theme = ThemeData(
        extensions: [
          HintTheme.minimal(ColorScheme.fromSeed(seedColor: Colors.teal))
              .copyWith(
            showPulse: true,
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          ),
        ],
      );

      await tester.pumpWidget(
        _harness(link: link, overlayKey: overlayKey, theme: theme),
      );
      final ctx = tester.element(find.byType(CompositedTransformTarget));
      registry.register(
          HintTargetRegistration(id: 'stats', link: link, context: ctx));

      final engine = HintOverlayEngine(
        registry: registry,
        input: input,
        overlay: overlayKey.currentState,
      );
      addTearDown(engine.dispose);
      engine.update(HintActive(tour: _tour('stats'), stepIndex: 0));
      await tester.pump(); // frame 1: position snapshot post-frame
      await tester.pump(); // blur strips + pulse + tooltip

      // Both layers are present…
      final pulseFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PulsePainter,
      );
      expect(pulseFinder, findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);

      // …and the pulse is a LATER child of the overlay Stack than the blur
      // scrim — a pulse inside the follower (an earlier child) would be
      // painted under the global BackdropFilter (the reported bug).
      bool isPulseLayer(Widget w) =>
          w is Positioned &&
          w.child is IgnorePointer &&
          (w.child as IgnorePointer).child is CustomPaint &&
          ((w.child as IgnorePointer).child as CustomPaint).painter
              is PulsePainter;
      // The blur layer is positioned, then movement-driven (a
      // ValueListenableBuilder around the ClipPath; see overlay_engine).
      bool isBlurLayer(Widget w) =>
          w is Positioned &&
          (w.child is ClipPath || w.child is ValueListenableBuilder<Offset?>);
      final overlayStack = tester
          .widgetList<Stack>(find.byType(Stack))
          .firstWhere((s) =>
              s.children.any(isPulseLayer) && s.children.any(isBlurLayer));
      expect(
        overlayStack.children.indexWhere(isPulseLayer),
        greaterThan(overlayStack.children.indexWhere(isBlurLayer)),
      );
    });
  });
}
