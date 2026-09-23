import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/src/engine/controller.dart';
import 'package:hintful/src/engine/diagnostics.dart';
import 'package:hintful/src/engine/machine.dart';
import 'package:hintful/src/engine/overlay/overlay_engine.dart';
import 'package:hintful/src/engine/registry.dart';
import 'package:hintful/src/engine/specs.dart';
import 'package:hintful/src/engine/store.dart';

HintTour _tour2() => HintTour(
      id: 't',
      steps: [
        HintStep(targetId: 'target0', title: 'A'),
        HintStep(targetId: 'target1', title: 'B'),
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

class _DiagRecorder {
  final List<HintSkipEvent> events = [];

  void call(HintSkipEvent event) => events.add(event);
}

class _RecordingHost implements HintOverlayHost {
  final List<HintState> updates = [];
  bool disposed = false;

  @override
  void update(HintState state) => updates.add(state);

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  group('HintController', () {
    test('headless + overlay is an assert (the two exclude each other)', () {
      expect(
        () => HintController(
          headless: true,
          overlay: () => null,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('registry getter is the one the controller wires over', () {
      final registry = HintTargetRegistry();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);
      expect(controller.registry, same(registry));
    });

    test(
        'diagnostics getter reports to the given handler (composed with '
        'the debug print in debug builds)', () {
      final diag = _DiagRecorder();
      final controller = HintController(
        registry: HintTargetRegistry(),
        diagnostics: diag.call,
        headless: true,
      );
      addTearDown(controller.dispose);
      // Not same(diag): the getter is the composed handler (debug print +
      // the user callback) — check the behavior, not the identity.
      controller.diagnostics!(const HintSkipEvent(
        tourId: 't',
        stepIndex: 0,
        targetId: 'x',
        reason: HintSkipReason.timeout,
        detail: 'did not appear',
      ));
      expect(diag.events, hasLength(1));
      expect(diag.events.single.tourId, 't');
    });

    test(
        'defaultOverlayHost wires controller.diagnostics into the engine '
        '(overlay failures are reported)', () {
      final diag = _DiagRecorder();
      final controller = HintController(
        registry: HintTargetRegistry(), // empty: nothing to capture from
        diagnostics: diag.call,
      );
      addTearDown(controller.dispose);

      final host = defaultOverlayHost()(controller);
      addTearDown(host.dispose);
      final tour = HintTour(
        id: 't',
        steps: const [HintStep(targetId: 'stats', title: 'Stats')],
      );

      host.update(HintWaiting(tour: tour, stepIndex: 0));

      expect(diag.events, hasLength(1));
      expect(
        diag.events.single.reason,
        HintSkipReason.overlayUnavailable,
      );
      expect(diag.events.single.tourId, 't');
      expect(diag.events.single.targetId, 'stats');

      // A persistent condition must report once per tour (host lifetime):
      // a second state change used to emit another overlayUnavailable event.
      host.update(HintActive(tour: tour, stepIndex: 0));
      host.update(HintWaiting(tour: tour, stepIndex: 0));

      expect(diag.events, hasLength(1));
    });

    testWidgets('start with a mounted target — immediately active step',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final host = _RecordingHost();
      final controller =
          HintController.withHost((_) => host, registry: registry);
      final tour = _tour2();
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.start(tour);

      expect(
        controller.currentState,
        HintActive(tour: tour, stepIndex: 0),
      );
      // Wiring of mounted targets: waiting first, then activation.
      expect(host.updates.first, HintWaiting(tour: tour, stepIndex: 0));
      expect(host.updates.last, HintActive(tour: tour, stepIndex: 0));
    });

    testWidgets('wait-for-target: the target appearing activates the step',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final host = _RecordingHost();
      final controller =
          HintController.withHost((_) => host, registry: registry);
      final tour = _tour2();
      addTearDown(controller.dispose);

      await controller.start(tour);
      expect(controller.currentState, HintWaiting(tour: tour, stepIndex: 0));

      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      await tester.pump(); // registry-sync microtask

      expect(controller.currentState, HintActive(tour: tour, stepIndex: 0));
    });

    testWidgets(
        'timeout without the target appearing — abort timeout + its '
        'diagnostics', (tester) async {
      final registry = HintTargetRegistry();
      final host = _RecordingHost();
      final diag = _DiagRecorder();
      final controller = HintController.withHost((_) => host,
          registry: registry, diagnostics: diag.call);
      final tour = _tour2();
      addTearDown(controller.dispose);

      await controller.start(tour);
      expect(controller.currentState, HintWaiting(tour: tour, stepIndex: 0));

      await tester.pump(const Duration(seconds: 3));

      expect(controller.currentState, isA<HintIdle>());
      expect(host.updates.last, isA<HintIdle>());
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
      final registry = HintTargetRegistry();
      final diag = _DiagRecorder();
      final host = _RecordingHost();
      final controller = HintController.withHost((_) => host,
          registry: registry, diagnostics: diag.call);
      final tour = _tour2();
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      registry.register(HintTargetRegistration(
        id: 'target1',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.start(tour);
      expect(controller.currentState, HintActive(tour: tour, stepIndex: 0));

      controller.next();
      expect(controller.currentState, HintActive(tour: tour, stepIndex: 1));

      controller.next();
      expect(controller.currentState, isA<HintIdle>());
      expect(diag.events, isEmpty,
          reason: 'a normal finish is not diagnosed as a skip');
    });

    testWidgets(
        'showHint: a one-step tour with no HintTour ceremony, '
        'next = finish', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final host = _RecordingHost();
      final controller =
          HintController.withHost((_) => host, registry: registry);
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'stats',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.showHint(HintStep(targetId: 'stats', title: 'One tip'));

      expect(controller.currentState, isA<HintActive>());
      expect(controller.currentState.tour?.id, 'hint:stats');

      controller.next();
      expect(controller.currentState, isA<HintIdle>(),
          reason: 'next on the only step = finish');
    });

    testWidgets('showHint: deferred target — the same waiting with id prefix',
        (tester) async {
      final registry = HintTargetRegistry();
      final controller = HintController(registry: registry, headless: true);

      await controller.showHint(HintStep(targetId: 'never', title: 'x'));

      expect(controller.currentState, isA<HintWaiting>());
      expect(controller.currentState.tour?.id, 'hint:never');
      expect(controller.currentState.stepIndex, 0);

      // In the test body, not in addTearDown: the "no pending timers" check
      // runs before teardown callbacks, and waiting holds a Timer for
      // stepTimeout.
      controller.dispose();
    });
    testWidgets('previous: next → previous returns to the previous step',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final host = _RecordingHost();
      final controller =
          HintController.withHost((_) => host, registry: registry);
      final tour = _tour2();
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      registry.register(HintTargetRegistration(
        id: 'target1',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.start(tour);
      controller.next();
      expect(controller.currentState, HintActive(tour: tour, stepIndex: 1));

      controller.previous();
      expect(controller.currentState, HintActive(tour: tour, stepIndex: 0));

      controller.previous(); // on the first step — a no-op
      expect(controller.currentState, HintActive(tour: tour, stepIndex: 0));
    });

    testWidgets('goTo: jump to a step; out of range — assert in debug',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      registry.register(HintTargetRegistration(
        id: 'target1',
        link: LayerLink(),
        context: ctx,
      ));

      final tour = _tour2();
      await controller.start(tour);
      controller.goTo(1);
      expect(controller.currentState, HintActive(tour: tour, stepIndex: 1));

      expect(
        () => controller.goTo(99),
        throwsA(isA<AssertionError>()),
      );
    });

    testWidgets(
        'skip on an active step — abort userSkipped with the step '
        'context', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final diag = _DiagRecorder();
      final controller = HintController(
        registry: registry,
        diagnostics: diag.call,
        headless: true,
      );
      final tour = _tour2();
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.start(tour);
      expect(controller.currentState, HintActive(tour: tour, stepIndex: 0));

      controller.skip();

      expect(controller.currentState, isA<HintIdle>());
      expect(diag.events, hasLength(1));
      expect(diag.events.single.reason, HintSkipReason.userSkipped);
      expect(diag.events.single.stepIndex, 0);
      expect(diag.events.single.targetId, 'target0');
    });

    testWidgets('no-op events do not notify state listeners', (tester) async {
      final registry = HintTargetRegistry();
      final controller = HintController(registry: registry, headless: true);
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
      final registry = HintTargetRegistry();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'statsPeriodSelector',
        link: LayerLink(),
        context: ctx,
      ));

      final typoTour = HintTour(
        id: 'typo',
        steps: const [
          HintStep(targetId: 'statsPeriodSelecor', title: 'Typo'),
        ],
      );

      // start is async: the AssertionError goes into the Future, it is not
      // thrown synchronously.
      await expectLater(
        controller.start(typoTour),
        throwsA(isA<AssertionError>()),
      );
      expect(controller.currentState, isA<HintIdle>(),
          reason: 'the tour did not start');
    });

    testWidgets('dispose: timer cancelled, host released, no events',
        (tester) async {
      final registry = HintTargetRegistry();
      final diag = _DiagRecorder();
      final host = _RecordingHost();
      final controller = HintController.withHost((_) => host,
          registry: registry, diagnostics: diag.call);

      await controller.start(_tour2()); // waiting(0) + 3s timer
      controller.dispose();

      await tester.pump(const Duration(seconds: 5));
      expect(host.disposed, isTrue);
      expect(diag.events, isEmpty, reason: 'no aborts after dispose');
    });
  });

  group('safe start (tryStart/restart/isIdle)', () {
    testWidgets('tryStart while busy — false, no assert, tour untouched',
        (tester) async {
      final registry = HintTargetRegistry();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      await controller.start(_tour2());
      expect(controller.isIdle, isFalse);

      // No AssertionError (unlike start): a plain false.
      expect(await controller.tryStart(_tour2()), isFalse);
      expect(controller.currentState.stepIndex, 0);

      controller.dispose();
    });

    testWidgets('tryStart while idle — starts and returns true',
        (tester) async {
      final registry = HintTargetRegistry();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      expect(controller.isIdle, isTrue);
      expect(await controller.tryStart(_tour2()), isTrue);
      expect(controller.isIdle, isFalse);

      controller.dispose();
    });

    testWidgets('restart replaces the running tour without diagnostics',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final diag = _DiagRecorder();
      final controller = HintController(
        registry: registry,
        diagnostics: diag.call,
        headless: true,
      );
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));
      registry.register(HintTargetRegistration(
        id: 'target1',
        link: LayerLink(),
        context: ctx,
      ));

      final first = _tour2();
      await controller.start(first);
      expect(controller.currentState, HintActive(tour: first, stepIndex: 0));

      final second = HintTour(
        id: 'second',
        steps: const [HintStep(targetId: 'target1', title: 'B')],
      );
      await controller.restart(second);

      expect(controller.currentState, HintActive(tour: second, stepIndex: 0));
      expect(diag.events, isEmpty,
          reason: 'restart finishes the old tour silently');
    });

    testWidgets('restart while idle — equivalent to start', (tester) async {
      final registry = HintTargetRegistry();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      await controller.restart(_tour2());
      expect(controller.currentState, isA<HintWaiting>());

      controller.dispose();
    });
  });

  group('startOnce (show-once: mark only on finish)', () {
    HintTour oneStep({String? minShowVersion}) => HintTour(
          id: 'intro',
          steps: const [HintStep(targetId: 'target0', title: 'A')],
          minShowVersion: minShowVersion,
        );

    testWidgets('gate closed — false, stays idle, no mark', (tester) async {
      final store = InMemoryHintStore()..markShown('intro', '1.0.0');
      final controller =
          HintController(registry: HintTargetRegistry(), headless: true);
      addTearDown(controller.dispose);

      expect(
        await controller.startOnce(
          oneStep(minShowVersion: '1.0.0'),
          store: store,
        ),
        isFalse,
      );
      expect(controller.isIdle, isTrue);
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isFalse);
    });

    testWidgets('finish marks shown for minVersion', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final store = InMemoryHintStore();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);
      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      expect(
        await controller.startOnce(
          oneStep(minShowVersion: '1.0.0'),
          store: store,
        ),
        isTrue,
      );
      expect(controller.isIdle, isFalse);
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue,
          reason: 'not marked until finish');

      controller.finish();
      expect(controller.isIdle, isTrue);
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isFalse);
    });

    testWidgets('skip does not mark — the tour may show again', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final store = InMemoryHintStore();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);
      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      expect(
        await controller.startOnce(
          oneStep(minShowVersion: '1.0.0'),
          store: store,
        ),
        isTrue,
      );
      controller.skip();
      expect(controller.isIdle, isTrue);
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue,
          reason: 'abort/skip must not mark');
    });

    testWidgets('timeout abort does not mark', (tester) async {
      final store = InMemoryHintStore();
      final controller =
          HintController(registry: HintTargetRegistry(), headless: true);
      addTearDown(controller.dispose);

      expect(
        await controller.startOnce(
          oneStep(minShowVersion: '1.0.0'),
          store: store,
        ),
        isTrue,
      );
      // No target registered → waiting, 3s default timeout.
      await tester.pump(const Duration(seconds: 3));
      expect(controller.isIdle, isTrue);
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue);
    });

    testWidgets('busy — false, no mark armed', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final store = InMemoryHintStore();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);
      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      expect(await controller.tryStart(_tour2()), isTrue);
      expect(
        await controller.startOnce(
          oneStep(minShowVersion: '1.0.0'),
          store: store,
        ),
        isFalse,
      );

      controller.finish();
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue,
          reason: 'busy startOnce never armed a mark');
    });

    testWidgets('plain start() of another tour does not mark the once key',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final store = InMemoryHintStore();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);
      for (final id in ['target0', 'target1']) {
        registry.register(HintTargetRegistration(
          id: id,
          link: LayerLink(),
          context: ctx,
        ));
      }

      expect(
        await controller.startOnce(
          oneStep(minShowVersion: '1.0.0'),
          store: store,
        ),
        isTrue,
      );
      controller.skip(); // disarms without mark
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue);

      await controller.start(_tour2());
      controller.finish();
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue,
          reason: 'a different tour finishing must not mark intro');
      expect(store.shouldShow('t', minVersion: '1.0.0'), isTrue,
          reason: 'plain start never marks');
    });

    testWidgets('version bump re-shows after a finish', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final store = InMemoryHintStore();
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);
      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      await controller.startOnce(
        oneStep(minShowVersion: '1.0.0'),
        store: store,
        version: '1.0.0',
      );
      controller.finish();
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isFalse);

      expect(
        await controller.startOnce(
          oneStep(minShowVersion: '1.1.0'),
          store: store,
          version: '1.1.0',
        ),
        isTrue,
      );
      controller.finish();
      expect(store.shouldShow('intro', minVersion: '1.1.0'), isFalse);
    });

    testWidgets('store on the controller — startOnce with no per-call store',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final store = InMemoryHintStore();
      final controller = HintController(
        registry: registry,
        headless: true,
        store: store,
      );
      addTearDown(controller.dispose);
      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      expect(
        await controller.startOnce(oneStep(minShowVersion: '1.0.0')),
        isTrue,
      );
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue,
          reason: 'not marked until finish');
      controller.finish();
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isFalse);
    });

    testWidgets('per-call store: overrides the controller store',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final controllerStore = InMemoryHintStore();
      final callStore = InMemoryHintStore();
      final controller = HintController(
        registry: registry,
        headless: true,
        store: controllerStore,
      );
      addTearDown(controller.dispose);
      registry.register(HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      ));

      expect(
        await controller.startOnce(
          oneStep(minShowVersion: '1.0.0'),
          store: callStore,
        ),
        isTrue,
      );
      controller.finish();
      expect(callStore.shouldShow('intro', minVersion: '1.0.0'), isFalse,
          reason: 'the per-call store wins');
      expect(controllerStore.shouldShow('intro', minVersion: '1.0.0'), isTrue,
          reason: 'the controller store stays untouched');
    });

    testWidgets('no store anywhere — debug assert, false, no start',
        (tester) async {
      final controller =
          HintController(registry: HintTargetRegistry(), headless: true);
      addTearDown(controller.dispose);

      await expectLater(
        controller.startOnce(oneStep(minShowVersion: '1.0.0')),
        throwsAssertionError,
      );
      expect(controller.isIdle, isTrue);
    });
  });

  group('scope (tabs sharing one registry)', () {
    testWidgets('out-of-scope targets do not activate steps', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final controller = HintController(
        registry: registry,
        scopePrefix: 'greenhouse-',
        headless: true,
      );
      addTearDown(controller.dispose);

      // A foreign screen's target with a similar id mounts first.
      registry.register(HintTargetRegistration(
        id: 'spread-target',
        link: LayerLink(),
        context: ctx,
      ));

      final tour = HintTour(
        id: 'g',
        steps: const [HintStep(targetId: 'greenhouse-target', title: 'x')],
      );
      await controller.start(tour);
      // Waiting: the foreign target must not satisfy the step.
      expect(controller.currentState, HintWaiting(tour: tour, stepIndex: 0));

      registry.register(HintTargetRegistration(
        id: 'greenhouse-target',
        link: LayerLink(),
        context: ctx,
      ));
      await tester.pump();
      expect(controller.currentState, HintActive(tour: tour, stepIndex: 0));
    });

    testWidgets('typo candidates ignore out-of-scope ids', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final controller = HintController(
        registry: registry,
        scopePrefix: 'greenhouse-',
        headless: true,
      );
      addTearDown(controller.dispose);

      // Only a foreign id is close to the typo: without scoping this would
      // assert as a typo; with scoping it is a legitimate deferred target.
      registry.register(HintTargetRegistration(
        id: 'spread-habit',
        link: LayerLink(),
        context: ctx,
      ));

      final tour = HintTour(
        id: 'g',
        steps: const [HintStep(targetId: 'greenhouse-habit', title: 'x')],
      );
      await controller.start(tour);
      expect(controller.currentState, HintWaiting(tour: tour, stepIndex: 0));

      controller.dispose();
    });
  });

  group('step lifecycle hooks (onStepEnter / onStepExit)', () {
    HintTour hookTour(
      List<String> log, {
      Future<void> Function()? enter0,
      Future<void> Function()? exit0,
      Future<void> Function()? enter1,
      Future<void> Function()? exit1,
    }) =>
        HintTour(
          id: 'hooks',
          steps: [
            HintStep(
              targetId: 'target0',
              title: 'A',
              onStepEnter: enter0,
              onStepExit: exit0,
            ),
            HintStep(
              targetId: 'target1',
              title: 'B',
              onStepEnter: enter1,
              onStepExit: exit1,
            ),
          ],
        );

    testWidgets(
        'order: old.exit → new.enter on step change; '
        'finish/skip fire exit for the open visit', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final log = <String>[];
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      for (final id in ['target0', 'target1']) {
        registry.register(HintTargetRegistration(
          id: id,
          link: LayerLink(),
          context: ctx,
        ));
      }

      final tour = hookTour(
        log,
        enter0: () async => log.add('enter0'),
        exit0: () async => log.add('exit0'),
        enter1: () async => log.add('enter1'),
        exit1: () async => log.add('exit1'),
      );

      await controller.start(tour);
      await tester.pump();
      expect(log, ['enter0']);

      controller.next();
      await tester.pump();
      expect(log, ['enter0', 'exit0', 'enter1'],
          reason: 'step change: exit(old) before enter(new)');

      controller.finish();
      await tester.pump();
      expect(log, ['enter0', 'exit0', 'enter1', 'exit1'],
          reason: 'finish ends the open visit');

      // skip on a fresh visit also fires exit
      await controller.start(hookTour(
        log,
        enter0: () async => log.add('enter0'),
        exit0: () async => log.add('exit0'),
      ));
      await tester.pump();
      controller.skip();
      await tester.pump();
      expect(log.last, 'exit0');
    });

    testWidgets(
        'async hooks run serialized: a slow enter does not interleave '
        'with exit/enter of the next step', (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final log = <String>[];
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      for (final id in ['target0', 'target1']) {
        registry.register(HintTargetRegistration(
          id: id,
          link: LayerLink(),
          context: ctx,
        ));
      }

      final tour = hookTour(
        log,
        enter0: () async {
          log.add('enter0:start');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          log.add('enter0:end');
        },
        exit0: () async => log.add('exit0'),
        enter1: () async => log.add('enter1'),
      );

      await controller.start(tour);
      await tester.pump(const Duration(milliseconds: 30));
      expect(log, ['enter0:start', 'enter0:end']);

      controller.next(); // fires while nothing is pending
      await tester.pump();
      expect(log, ['enter0:start', 'enter0:end', 'exit0', 'enter1']);
    });

    testWidgets('target vanish/reappear does not re-fire hooks (one visit)',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final log = <String>[];
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      final reg = HintTargetRegistration(
        id: 'target0',
        link: LayerLink(),
        context: ctx,
      );
      registry.register(reg);

      final tour = hookTour(
        log,
        enter0: () async => log.add('enter0'),
        exit0: () async => log.add('exit0'),
        enter1: () async => log.add('enter1'),
      );

      await controller.start(tour);
      await tester.pump();
      expect(log, ['enter0']);
      expect(controller.currentState, isA<HintActive>());

      registry.unregister(reg); // Active → Waiting (same step)
      await tester.pump();
      expect(controller.currentState, isA<HintWaiting>());
      expect(log, ['enter0'], reason: 'vanish keeps the visit open');

      registry.register(reg); // Waiting → Active (same step)
      await tester.pump();
      expect(controller.currentState, isA<HintActive>());
      expect(log, ['enter0'], reason: 'reappear does not re-fire enter');

      controller.finish();
      await tester.pump();
      expect(log, ['enter0', 'exit0']);
    });

    testWidgets('a throwing hook is reported and does not break the chain',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final log = <String>[];
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      for (final id in ['target0', 'target1']) {
        registry.register(HintTargetRegistration(
          id: id,
          link: LayerLink(),
          context: ctx,
        ));
      }

      final tour = hookTour(
        log,
        enter0: () async {
          log.add('enter0');
          throw StateError('boom');
        },
        exit0: () async => log.add('exit0'),
        enter1: () async => log.add('enter1'),
      );

      await controller.start(tour);
      await tester.pump();
      expect(log, ['enter0']);

      controller.next();
      await tester.pump();
      expect(log, ['enter0', 'exit0', 'enter1'],
          reason: 'exit/enter still run after a throwing enter');
    });

    // The release busy guard (`if (!isIdle) return;` in start) is covered by
    // code review only: the debug assert fires first under `flutter test`
    // (assert-parity) — same treatment as the repo's other release-only
    // branches.
    testWidgets(
        'a throwing hook is logged through debugPrint (release contract)',
        (tester) async {
      final lines = <String>[];
      final old = debugPrint;
      debugPrint = (msg, {wrapWidth}) => lines.add(msg ?? '');

      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final log = <String>[];
      final controller = HintController(registry: registry, headless: true);
      addTearDown(controller.dispose);

      for (final id in ['target0', 'target1']) {
        registry.register(HintTargetRegistration(
          id: id,
          link: LayerLink(),
          context: ctx,
        ));
      }

      final tour = hookTour(
        log,
        enter0: () async {
          log.add('enter0');
          throw StateError('boom');
        },
        exit0: () async => log.add('exit0'),
        enter1: () async => log.add('enter1'),
      );

      try {
        await controller.start(tour);
        await tester.pump();
        controller.next();
        await tester.pump();
      } finally {
        // Restore inline (not addTearDown): the test binding verifies
        // foundation debug vars are unset before teardown callbacks run.
        debugPrint = old;
      }

      expect(log, ['enter0', 'exit0', 'enter1'],
          reason: 'the chain still continues after the logged throw');
      expect(
        lines.where((l) =>
            l.contains('step lifecycle hook threw') && l.contains('boom')),
        isNotEmpty,
        reason: 'the hook failure must be logged, not swallowed',
      );
    });
  });

  group('skipStep policy (controller integration)', () {
    testWidgets('timeout skips the step and the tour continues',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final registry = HintTargetRegistry();
      final diag = _DiagRecorder();
      final host = _RecordingHost();
      final controller = HintController.withHost((_) => host,
          registry: registry, diagnostics: diag.call);
      addTearDown(controller.dispose);

      registry.register(HintTargetRegistration(
        id: 'target1',
        link: LayerLink(),
        context: ctx,
      ));

      final tour = HintTour(
        id: 't',
        missingTargetPolicy: HintMissingTargetPolicy.skipStep,
        // The missing step times out fast; the present step waits normally.
        steps: [
          HintStep(
            targetId: 'target0',
            title: 'Missing',
            stepTimeout: const Duration(milliseconds: 10),
          ),
          HintStep(targetId: 'target1', title: 'Present'),
        ],
      );
      await controller.start(tour);
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.currentState.stepIndex, 1);
      expect(controller.currentState, isA<HintActive>());
      expect(diag.events, hasLength(1));
      expect(diag.events.single.reason, HintSkipReason.timeout);
      expect(diag.events.single.stepIndex, 0);
      expect(diag.events.single.targetId, 'target0');

      // The tour continues to a normal finish (no abort).
      controller.next();
      expect(controller.currentState, isA<HintIdle>());
    });
  });

  group('classifyStepTargets (typo classification)', () {
    test('valid / typos with candidates / deferred are separated', () {
      const known = {'statsPeriodSelector', 'addSet'};
      final tour = HintTour(
        id: 't',
        steps: [
          const HintStep(targetId: 'addSet', title: 'valid'),
          const HintStep(targetId: 'statsPeriodSelectr', title: 'typo'),
          const HintStep(targetId: 'futureThing', title: 'deferred'),
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
      final tour = HintTour(
        id: 't',
        steps: [
          const HintStep(targetId: 'target9', title: 'next step'),
          const HintStep(targetId: 'statsPeriodSelectr', title: 'typo'),
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
      final tour = HintTour(
        id: 't',
        steps: const [
          HintStep(targetId: 'anything', title: 'x'),
        ],
      );
      final classification = classifyStepTargets(tour, const {});
      expect(classification.deferred, hasLength(1));
      expect(classification.typos, isEmpty);
    });

    test('a typo in a multi-target step is reported with the offending id', () {
      const known = {'statsPeriodSelector', 'addSet'};
      final tour = HintTour(
        id: 't',
        steps: [
          const HintStep(
            targetId: 'addSet',
            moreTargets: ['statsPeriodSelectr'], // the typo is the extra
            title: 'multi',
          ),
        ],
      );

      final classification = classifyStepTargets(tour, known);

      expect(classification.typos, hasLength(1));
      expect(classification.typos.single.index, 0);
      expect(classification.typos.single.typoId, 'statsPeriodSelectr');
      expect(
        classification.typos.single.candidates,
        ['statsPeriodSelector'],
      );
    });
  });
}
