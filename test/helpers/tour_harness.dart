import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/hintful.dart';

/// A harness-scene target: id + position. The container is labelled with the
/// id so a test can find the target via `find.text(id)`.
class HarnessTarget {
  const HarnessTarget(
    this.id, {
    this.left = 20,
    this.top = 40,
    this.width = 120,
    this.height = 60,
  });

  final String id;
  final double left;
  final double top;
  final double width;
  final double height;
}

/// A diagnostics record: the skip/abort reason with the step context.
typedef HintSkipRecord = ({
  String tourId,
  int stepIndex,
  String targetId,
  HintSkipReason reason,
  String detail,
});

/// Diagnostics collector — shared by the flow tests (timeout, skip, typo).
class DiagnosticsRecorder implements HintDiagnosticsHandler {
  final List<HintSkipRecord> events = [];

  @override
  void onHintSkipped(
    String tourId,
    int stepIndex,
    String targetId,
    HintSkipReason reason,
    String detail,
  ) {
    events.add((
      tourId: tourId,
      stepIndex: stepIndex,
      targetId: targetId,
      reason: reason,
      detail: detail,
    ));
  }
}

/// Widget-test harness for tours.
///
/// One call — a scene like in an app: MaterialApp + Scaffold + targets (real
/// `HintTarget`s) + the MaterialApp root Overlay + a controller with a
/// real `HintOverlayEngine` (`defaultOverlayHost`). A new widget test is a
/// few lines instead of ~40 lines of manual wiring.
///
/// ```dart
/// final h = TourHarness(targets: [HarnessTarget('stats')]);
/// await h.pump(tester);
/// await h.start(tester, HintTour(id: 't', steps: [
///   HintStep(targetId: 'stats', title: 'Title'),
/// ]));
/// expect(find.text('Title'), findsOneWidget);
/// await tester.tap(find.text('Done'));
/// await tester.pump();
/// h.expectIdleClean(); // zero engine widgets in the tree when idle
/// ```
class TourHarness {
  TourHarness({
    this.targets = const [],
    HintTargetRegistry? registry,
    HintDiagnosticsHandler? diagnostics,
    this.scrollable = false,
    this.themeExtensions = const [],
  })  : registry = registry ?? HintTargetRegistry(),
        diagnostics = diagnostics ?? DiagnosticsRecorder();

  /// Scene targets; [reveal] adds more at runtime (deferred scenario).
  final List<HarnessTarget> targets;
  final HintTargetRegistry registry;
  final HintDiagnosticsHandler diagnostics;

  /// `ThemeData.extensions` of the scene (a custom [HintTheme] — e.g.
  /// `showTail: false`). Empty — the zero-config minimal default.
  final List<ThemeExtension<dynamic>> themeExtensions;

  /// true — targets sit vertically in a `ListView` (scroll scenarios:
  /// following, deferred below the edge); false — a fixed Stack. In the
  /// scrollable mode `HarnessTarget.top` is the offset before the target.
  final bool scrollable;

  /// Scroll controller of the scrollable scene: a test can scroll it
  /// programmatically (the scrim blocks user drag — the tour owns the
  /// screen; scroll-through is follow-up work).
  final ScrollController scrollController = ScrollController();

  /// Controller with a real engine; created in [pump], released
  /// automatically (addTearDown).
  late final HintController controller;
  bool _pumped = false;
  final List<HarnessTarget> _extra = [];

  /// Mount the scene (idempotent): the controller is created once per
  /// harness, repeated calls rebuild the widget tree.
  Future<void> pump(WidgetTester tester) async {
    if (!_pumped) {
      _pumped = true;
      controller = HintController(
        registry: registry,
        diagnostics: diagnostics,
        overlayHostBuilder: defaultOverlayHost(registry: registry),
      );
      addTearDown(_disposeOnce);
    }
    await tester.pumpWidget(_scene());
  }

  /// Release the controller inside a test body. Needed by tests that end in
  /// a waiting state: it holds a Timer for waitTimeout, and the "no pending
  /// timers" check runs BEFORE teardown callbacks (same reason as in
  /// controller_test). Idempotent — a teardown call after [disposeNow] is
  /// safe.
  void disposeNow() {
    if (_pumped) _disposeOnce();
  }

  bool _disposed = false;

  void _disposeOnce() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    scrollController.dispose();
  }

  /// Mount an extra target: wait-for-target → active step. Rebuilding the
  /// scene mounts a new `HintTarget` (initState → registration); the
  /// existing widgets/states are preserved.
  Future<void> reveal(WidgetTester tester, HarnessTarget target) async {
    _extra.add(target);
    await tester.pumpWidget(_scene());
  }

  /// Start the tour + two pumps: a scrim frame, then the tooltip on top of
  /// the snapshot.
  Future<void> start(WidgetTester tester, HintTour tour) async {
    await controller.start(tour);
    await settle(tester);
  }

  /// Two pumps after a state change: scrim frame → tooltip/next step.
  static Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// Zero-idle assertion: when idle, the tree has no engine widget at all
  /// (the overlay is removed).
  void expectIdleClean() {
    expect(find.byType(DefaultTooltip), findsNothing,
        reason: 'idle: no tooltip');
    expect(_scrimFinder, findsNothing, reason: 'idle: no scrim');
    expect(find.text('Preparing…'), findsNothing,
        reason: 'idle: no waiting layer');
    expect(find.byType(CompositedTransformFollower), findsNothing,
        reason: 'idle: no follower (it lives inside the entry)');
  }

  /// The scrim layer — a `CustomPaint` with `ScrimHolePainter` (the shared
  /// test predicate).
  static final Finder scrimFinder = _scrimFinder;

  static final Finder _scrimFinder = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is ScrimHolePainter,
  );

  Widget _scene() {
    final targets = [...this.targets, ..._extra];

    Widget target(HarnessTarget t) => HintTarget(
          id: t.id,
          registry: registry,
          child: Container(
            width: scrollable ? double.infinity : t.width,
            height: t.height,
            color: Colors.blue,
            alignment: Alignment.center,
            child: Text(
              t.id,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );

    final Widget body = scrollable
        ? ListView(
            controller: scrollController,
            children: [
              for (final t in targets) ...[SizedBox(height: t.top), target(t)],
            ],
          )
        : Stack(
            children: [
              for (final t in targets)
                Positioned(
                  left: t.left,
                  top: t.top,
                  child: target(t),
                ),
            ],
          );

    return MaterialApp(
      theme: ThemeData(extensions: themeExtensions),
      home: Scaffold(body: body),
    );
  }
}
