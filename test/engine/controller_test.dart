import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/controller.dart';
import 'package:hintful/engine/diagnostics.dart';
import 'package:hintful/engine/machine.dart';
import 'package:hintful/engine/registry.dart';
import 'package:hintful/engine/specs.dart';

TourSpec _tour2() => TourSpec(
      id: 't',
      steps: [
        StepSpec(targetId: 'target0', title: 'A'),
        StepSpec(targetId: 'target1', title: 'B'),
      ],
    );

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    Builder(
      builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      },
    ),
  );
  return captured;
}

class _DiagRecorder implements HintDiagnosticsHandler {
  final List<
      ({
        String tourId,
        int stepIndex,
        String targetId,
        HintSkipReason reason,
        String detail,
      })> events = [];

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

class _RecordingHost implements TourOverlayHost {
  final List<TourState> updates = [];
  bool disposed = false;

  @override
  void update(TourState state) => updates.add(state);

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  group('ShowcaseController', () {
    testWidgets('start with a mounted target — immediately active step',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = TargetRegistry();
      final host = _RecordingHost();
      final controller = ShowcaseController(
        registry: registry,
        overlayHostBuilder: (_) => host,
      );
      final tour = _tour2();
      addTearDown(controller.dispose);

      registry.register(TargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.start(tour);

      expect(
        controller.currentState,
        TourActive(tour: tour, stepIndex: 0),
      );
      // Wiring of mounted targets: waiting first, then activation.
      expect(host.updates.first, TourWaiting(tour: tour, stepIndex: 0));
      expect(host.updates.last, TourActive(tour: tour, stepIndex: 0));
    });

    testWidgets('wait-for-target: the target appearing activates the step',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = TargetRegistry();
      final host = _RecordingHost();
      final controller = ShowcaseController(
        registry: registry,
        overlayHostBuilder: (_) => host,
      );
      final tour = _tour2();
      addTearDown(controller.dispose);

      await controller.start(tour);
      expect(controller.currentState, TourWaiting(tour: tour, stepIndex: 0));

      registry.register(TargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      await tester.pump(); // registry-sync microtask

      expect(controller.currentState, TourActive(tour: tour, stepIndex: 0));
    });

    testWidgets(
        'timeout without the target appearing — abort timeout + its '
        'diagnostics', (tester) async {
      final registry = TargetRegistry();
      final host = _RecordingHost();
      final diag = _DiagRecorder();
      final controller = ShowcaseController(
        registry: registry,
        diagnostics: diag,
        overlayHostBuilder: (_) => host,
      );
      final tour = _tour2();
      addTearDown(controller.dispose);

      await controller.start(tour);
      expect(controller.currentState, TourWaiting(tour: tour, stepIndex: 0));

      await tester.pump(const Duration(seconds: 3));

      expect(controller.currentState, isA<TourIdle>());
      expect(host.updates.last, isA<TourIdle>());
      expect(diag.events, hasLength(1));
      expect(diag.events.single.reason, HintSkipReason.timeout);
      expect(diag.events.single.tourId, 't');
      expect(diag.events.single.stepIndex, 0);
      expect(diag.events.single.targetId, 'target0');
      expect(diag.events.single.detail, contains('did not appear'));
    });

    testWidgets(
        'tour walkthrough: next to the end — finish without '
        'diagnostics', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = TargetRegistry();
      final diag = _DiagRecorder();
      final host = _RecordingHost();
      final controller = ShowcaseController(
        registry: registry,
        diagnostics: diag,
        overlayHostBuilder: (_) => host,
      );
      final tour = _tour2();
      addTearDown(controller.dispose);

      registry.register(TargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      registry.register(TargetRegistration(
        id: 'target1',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.start(tour);
      expect(controller.currentState, TourActive(tour: tour, stepIndex: 0));

      controller.next();
      expect(controller.currentState, TourActive(tour: tour, stepIndex: 1));

      controller.next();
      expect(controller.currentState, isA<TourIdle>());
      expect(diag.events, isEmpty,
          reason: 'a normal finish is not diagnosed as a skip');
    });

    testWidgets(
        'showHint: a one-step tour with no TourSpec ceremony, '
        'next = finish', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = TargetRegistry();
      final host = _RecordingHost();
      final controller = ShowcaseController(
        registry: registry,
        overlayHostBuilder: (_) => host,
      );
      addTearDown(controller.dispose);

      registry.register(TargetRegistration(
        id: 'stats',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.showHint(StepSpec(targetId: 'stats', title: 'One tip'));

      expect(controller.currentState, isA<TourActive>());
      expect(controller.currentState.tour?.id, 'hint:stats');

      controller.next();
      expect(controller.currentState, isA<TourIdle>(),
          reason: 'next on the only step = finish');
    });

    testWidgets('showHint: deferred target — the same waiting with id prefix',
        (tester) async {
      final registry = TargetRegistry();
      final controller = ShowcaseController(registry: registry);

      await controller.showHint(StepSpec(targetId: 'never', title: 'x'));

      expect(controller.currentState, isA<TourWaiting>());
      expect(controller.currentState.tour?.id, 'hint:never');
      expect(controller.currentState.stepIndex, 0);

      // In the test body, not in addTearDown: the "no pending timers" check
      // runs before teardown callbacks, and waiting holds a Timer for
      // waitTimeout.
      controller.dispose();
    });
    testWidgets('previous: next → previous returns to the previous step',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = TargetRegistry();
      final host = _RecordingHost();
      final controller = ShowcaseController(
        registry: registry,
        overlayHostBuilder: (_) => host,
      );
      final tour = _tour2();
      addTearDown(controller.dispose);

      registry.register(TargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      registry.register(TargetRegistration(
        id: 'target1',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.start(tour);
      controller.next();
      expect(controller.currentState, TourActive(tour: tour, stepIndex: 1));

      controller.previous();
      expect(controller.currentState, TourActive(tour: tour, stepIndex: 0));

      controller.previous(); // on the first step — a no-op
      expect(controller.currentState, TourActive(tour: tour, stepIndex: 0));
    });

    testWidgets('goTo: jump to a step; out of range — assert in debug',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = TargetRegistry();
      final controller = ShowcaseController(registry: registry);
      addTearDown(controller.dispose);

      registry.register(TargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      registry.register(TargetRegistration(
        id: 'target1',
        link: LayerLink(),
        context: ctx,
      ));

      final tour = _tour2();
      await controller.start(tour);
      controller.goTo(1);
      expect(controller.currentState, TourActive(tour: tour, stepIndex: 1));

      expect(
        () => controller.goTo(99),
        throwsA(isA<AssertionError>()),
      );
    });

    testWidgets(
        'skip on an active step — abort userSkipped with the step '
        'context', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = TargetRegistry();
      final diag = _DiagRecorder();
      final controller = ShowcaseController(
        registry: registry,
        diagnostics: diag,
      );
      final tour = _tour2();
      addTearDown(controller.dispose);

      registry.register(TargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.start(tour);
      expect(controller.currentState, TourActive(tour: tour, stepIndex: 0));

      controller.skip();

      expect(controller.currentState, isA<TourIdle>());
      expect(diag.events, hasLength(1));
      expect(diag.events.single.reason, HintSkipReason.userSkipped);
      expect(diag.events.single.stepIndex, 0);
      expect(diag.events.single.targetId, 'target0');
    });

    testWidgets('no-op events do not notify state listeners', (tester) async {
      final registry = TargetRegistry();
      final controller = ShowcaseController(registry: registry);
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.state.addListener(() => notifications++);

      controller.next(); // in idle — a no-op
      controller.skip();
      controller.finish();

      expect(notifications, 0);
    });

    testWidgets(
        'unresolvable targetId: AssertionError with closest id in '
        'debug', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = TargetRegistry();
      final controller = ShowcaseController(registry: registry);
      addTearDown(controller.dispose);

      registry.register(TargetRegistration(
        id: 'statsPeriodSelector',
        link: LayerLink(),
        context: ctx,
      ));

      final typoTour = TourSpec(
        id: 'typo',
        steps: const [
          StepSpec(targetId: 'statsPeriodSelecor', title: 'Typo'),
        ],
      );

      // start is async: the AssertionError goes into the Future, it is not
      // thrown synchronously.
      await expectLater(
        controller.start(typoTour),
        throwsA(isA<AssertionError>()),
      );
      expect(controller.currentState, isA<TourIdle>(),
          reason: 'the tour did not start');
    });

    testWidgets('dispose: timer cancelled, host released, no events',
        (tester) async {
      final registry = TargetRegistry();
      final diag = _DiagRecorder();
      final host = _RecordingHost();
      final controller = ShowcaseController(
        registry: registry,
        diagnostics: diag,
        overlayHostBuilder: (_) => host,
      );

      await controller.start(_tour2()); // waiting(0) + 3s timer
      controller.dispose();

      await tester.pump(const Duration(seconds: 5));
      expect(host.disposed, isTrue);
      expect(diag.events, isEmpty, reason: 'no aborts after dispose');
    });
  });

  group('classifyStepTargets (typo classification)', () {
    test('valid / typos with candidates / deferred are separated', () {
      const known = {'statsPeriodSelector', 'addSet'};
      final tour = TourSpec(
        id: 't',
        steps: [
          const StepSpec(targetId: 'addSet', title: 'valid'),
          const StepSpec(targetId: 'statsPeriodSelectr', title: 'typo'),
          const StepSpec(targetId: 'futureThing', title: 'deferred'),
        ],
      );

      final classification = classifyStepTargets(tour, known);

      expect(
        classification.deferred.map((s) => s.targetId),
        ['futureThing'],
      );
      expect(classification.typos, hasLength(1));
      expect(classification.typos.single.index, 1);
      expect(
        classification.typos.single.candidates,
        ['statsPeriodSelector'],
      );
    });

    test('differing only in digits — a sequence, not a typo', () {
      const known = {'target0', 'statsPeriodSelector'};
      final tour = TourSpec(
        id: 't',
        steps: [
          const StepSpec(targetId: 'target9', title: 'next step'),
          const StepSpec(targetId: 'statsPeriodSelectr', title: 'typo'),
        ],
      );

      final classification = classifyStepTargets(tour, known);

      expect(
        classification.deferred.map((s) => s.targetId),
        ['target9'],
      );
      expect(classification.typos, hasLength(1));
      expect(classification.typos.single.step.targetId, 'statsPeriodSelectr');
    });

    test('empty registry — all steps deferred, no typos', () {
      final tour = TourSpec(
        id: 't',
        steps: const [
          StepSpec(targetId: 'anything', title: 'x'),
        ],
      );
      final classification = classifyStepTargets(tour, const {});
      expect(classification.deferred, hasLength(1));
      expect(classification.typos, isEmpty);
    });
  });
}
