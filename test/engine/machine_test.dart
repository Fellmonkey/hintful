import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/diagnostics.dart';
import 'package:hintful/engine/machine.dart';
import 'package:hintful/engine/specs.dart';

HintTour _tour({
  int steps = 2,
  Duration stepTimeout = const Duration(seconds: 3),
}) =>
    HintTour(
      id: 't',
      steps: [
        for (var i = 0; i < steps; i++)
          HintStep(targetId: 'target$i', title: 'Step $i'),
      ],
      stepTimeout: stepTimeout,
    );

void expectTransition(
  HintTransition transition,
  HintState state,
  List<HintEffect> effects,
) {
  expect(transition.effects, effects, reason: 'effects');
  expect(transition.state, state, reason: 'state');
}

void main() {
  group('transition table (data → loop)', () {
    final tour = _tour();
    const idle = HintIdle();
    final waiting0 = HintWaiting(tour: tour, stepIndex: 0);
    final active0 = HintActive(tour: tour, stepIndex: 0);
    final waiting1 = HintWaiting(tour: tour, stepIndex: 1);
    final active1 = HintActive(tour: tour, stepIndex: 1);
    const arm3 = ArmTimeoutEffect(timeout: Duration(seconds: 3));

    final cases = <({
      String name,
      HintState from,
      HintEvent event,
      Map<String, bool> present,
      HintState expected,
      List<HintEffect> effects,
    })>[
      (
        name: 'start from idle → waiting(0) + timer',
        from: idle,
        event: HintStart(tour: tour),
        present: const {},
        expected: waiting0,
        effects: const [arm3],
      ),
      (
        name: 'idle ignores everything except start',
        from: idle,
        event: const UserFinish(),
        present: const {},
        expected: idle,
        effects: const [],
      ),
      (
        name: 'idle ignores foreign targets appearing',
        from: idle,
        event: const TargetAppeared(targetId: 'target0'),
        present: const {},
        expected: idle,
        effects: const [],
      ),
      (
        name: 'the awaited target appears → active + show step',
        from: waiting0,
        event: const TargetAppeared(targetId: 'target0'),
        present: const {},
        expected: active0,
        effects: const [
          ClearTimeoutEffect(),
          EnterStepEffect(stepIndex: 0),
        ],
      ),
      (
        name: 'a foreign target appearing while waiting is ignored',
        from: waiting0,
        event: const TargetAppeared(targetId: 'target1'),
        present: const {},
        expected: waiting0,
        effects: const [],
      ),
      (
        name: 'timeout while waiting → abort timeout',
        from: waiting0,
        event: const WaitTimeout(),
        present: const {},
        expected: idle,
        effects: const [
          ClearTimeoutEffect(),
          AbortEffect(
            reason: HintSkipReason.timeout,
            detail: "target 'target0' did not appear within 0:00:03.000000",
          ),
        ],
      ),
      (
        name: 'next while waiting does not skip the wait',
        from: waiting0,
        event: const UserNext(),
        present: const {},
        expected: waiting0,
        effects: const [],
      ),
      (
        name: 'skip while waiting → abort userSkipped',
        from: waiting0,
        event: const UserSkip(),
        present: const {},
        expected: idle,
        effects: const [
          ClearTimeoutEffect(),
          AbortEffect(
            reason: HintSkipReason.userSkipped,
            detail: 'user skipped',
          ),
        ],
      ),
      (
        name: 'finish while waiting → normal completion',
        from: waiting0,
        event: const UserFinish(),
        present: const {},
        expected: idle,
        effects: const [
          ClearTimeoutEffect(),
          FinishedEffect(tourId: 't'),
        ],
      ),
      (
        name: 'any target vanishing while waiting — keep waiting',
        from: waiting0,
        event: const TargetVanished(targetId: 'target0'),
        present: const {},
        expected: waiting0,
        effects: const [],
      ),
      (
        name: 'the current target vanishing on an active step → abort '
            'unmounted',
        from: active0,
        event: const TargetVanished(targetId: 'target0'),
        present: const {},
        expected: idle,
        effects: const [
          AbortEffect(
            reason: HintSkipReason.targetUnmountedDuringStep,
            detail: "target 'target0' unmounted during step 1",
          ),
        ],
      ),
      (
        name: 'a future target vanishing does not touch the active step',
        from: active0,
        event: const TargetVanished(targetId: 'target1'),
        present: const {},
        expected: active0,
        effects: const [],
      ),
      (
        name: 'timeout while active is ignored (no timer is armed)',
        from: active0,
        event: const WaitTimeout(),
        present: const {},
        expected: active0,
        effects: const [],
      ),
      (
        name: 'previous from active step 1 → step 0 (target present)',
        from: active1,
        event: const UserPrevious(),
        present: const {'target0': true},
        expected: active0,
        effects: const [EnterStepEffect(stepIndex: 0)],
      ),
      (
        name: 'previous without step-0 target → waiting step 0 + timer',
        from: active1,
        event: const UserPrevious(),
        present: const {},
        expected: waiting0,
        effects: const [arm3],
      ),
      (
        name: 'previous on the first step — a no-op',
        from: active0,
        event: const UserPrevious(),
        present: const {},
        expected: active0,
        effects: const [],
      ),
      (
        name: 'previous from waiting step 1 → active step 0 (timer cleared)',
        from: waiting1,
        event: const UserPrevious(),
        present: const {'target0': true},
        expected: active0,
        effects: const [
          ClearTimeoutEffect(),
          EnterStepEffect(stepIndex: 0),
        ],
      ),
      (
        name: 'previous from waiting without the target → re-arm on step 0',
        from: waiting1,
        event: const UserPrevious(),
        present: const {},
        expected: waiting0,
        effects: const [arm3],
      ),
      (
        name: 'previous from waiting on the first step — no-op (timer kept)',
        from: waiting0,
        event: const UserPrevious(),
        present: const {},
        expected: waiting0,
        effects: const [],
      ),
      (
        name: 'goTo(1) with the target present → active step 1',
        from: active0,
        event: const UserGoTo(index: 1),
        present: const {'target1': true},
        expected: active1,
        effects: const [EnterStepEffect(stepIndex: 1)],
      ),
      (
        name: 'goTo(1) without the target → waiting step 1 + timer',
        from: active0,
        event: const UserGoTo(index: 1),
        present: const {},
        expected: waiting1,
        effects: const [arm3],
      ),
      (
        name: 'goTo(0) from active step 1 — back by index',
        from: active1,
        event: const UserGoTo(index: 0),
        present: const {'target0': true},
        expected: active0,
        effects: const [EnterStepEffect(stepIndex: 0)],
      ),
      (
        name: 'goTo the current index — a no-op',
        from: active1,
        event: const UserGoTo(index: 1),
        present: const {},
        expected: active1,
        effects: const [],
      ),
      (
        name: 'goTo from waiting → active step (timer cleared)',
        from: waiting0,
        event: const UserGoTo(index: 1),
        present: const {'target1': true},
        expected: active1,
        effects: const [
          ClearTimeoutEffect(),
          EnterStepEffect(stepIndex: 1),
        ],
      ),
      (
        name: 'goTo from waiting without the target → re-arm on target step',
        from: waiting0,
        event: const UserGoTo(index: 1),
        present: const {},
        expected: waiting1,
        effects: const [arm3],
      ),
      (
        name: 'next with a present target → immediately active step',
        from: active0,
        event: const UserNext(),
        present: const {'target1': true},
        expected: active1,
        effects: const [EnterStepEffect(stepIndex: 1)],
      ),
      (
        name: 'next without the target → waiting the next step + timer',
        from: active0,
        event: const UserNext(),
        present: const {},
        expected: waiting1,
        effects: const [arm3],
      ),
      (
        name: 'next on the last step → normal completion',
        from: active1,
        event: const UserNext(),
        present: const {},
        expected: idle,
        effects: const [FinishedEffect(tourId: 't')],
      ),
      (
        name: 'skip on an active step → abort userSkipped',
        from: active0,
        event: const UserSkip(),
        present: const {},
        expected: idle,
        effects: const [
          AbortEffect(
            reason: HintSkipReason.userSkipped,
            detail: 'user skipped',
          ),
        ],
      ),
      (
        name: 'finish on an active step → normal completion',
        from: active0,
        event: const UserFinish(),
        present: const {},
        expected: idle,
        effects: const [FinishedEffect(tourId: 't')],
      ),
      (
        name: 'a target appearing on an active step — a no-op',
        from: active1,
        event: const TargetAppeared(targetId: 'target0'),
        present: const {},
        expected: active1,
        effects: const [],
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        final machine = HintMachine(initialState: c.from);
        final transition = machine.dispatch(
          c.event,
          targetPresent: (id) => c.present[id] ?? false,
        );
        expectTransition(transition, c.expected, c.effects);
        // The machine state is in sync with the transition result.
        expect(machine.state, c.expected);
      });
    }
  });

  group('wait-for-target on every step', () {
    test('per-step waitTimeout overrides the tour stepTimeout', () {
      final tour = HintTour(
        id: 't',
        stepTimeout: const Duration(seconds: 3),
        steps: [
          HintStep(
            targetId: 'a',
            title: 'A',
            waitTimeout: const Duration(seconds: 7),
          ),
          HintStep(targetId: 'b', title: 'B'),
        ],
      );
      final machine = HintMachine();

      final start = machine.dispatch(HintStart(tour: tour));
      expect(
        start.effects,
        const [ArmTimeoutEffect(timeout: Duration(seconds: 7))],
      );

      machine.dispatch(const TargetAppeared(targetId: 'a'));
      final next = machine.dispatch(const UserNext());
      expect(machine.state, HintWaiting(tour: tour, stepIndex: 1));
      expect(
        next.effects,
        const [ArmTimeoutEffect(timeout: Duration(seconds: 3))],
      );
    });
  });

  group('contracts', () {
    test('a second start over an active tour — assert in debug', () {
      final tour = _tour();
      final machine = HintMachine();
      machine.dispatch(HintStart(tour: tour));
      expect(
        () => machine.dispatch(HintStart(tour: tour)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('state equality — by tour (identity) and step', () {
      final tour = _tour();
      expect(HintWaiting(tour: tour, stepIndex: 0),
          HintWaiting(tour: tour, stepIndex: 0));
      expect(HintWaiting(tour: tour, stepIndex: 0),
          isNot(HintWaiting(tour: tour, stepIndex: 1)));
      expect(HintActive(tour: tour, stepIndex: 0),
          isNot(HintWaiting(tour: tour, stepIndex: 0)));
      expect(const HintIdle(), const HintIdle());
    });

    test('goTo out of range — assert in debug', () {
      final tour = _tour();
      final machine = HintMachine();
      machine.dispatch(HintStart(tour: tour));
      machine.dispatch(const TargetAppeared(targetId: 'target0'));
      expect(
        () => machine.dispatch(const UserGoTo(index: 99)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('fuzz: random sequences', () {
    test('10 000 events — invariants hold', () {
      final tour = _tour(steps: 3);
      final rng = Random(42);
      const ids = ['target0', 'target1', 'target2', 'ghost'];
      var total = 0;

      for (var run = 0; run < 10; run++) {
        final machine = HintMachine();
        // Target presence is fixed for the whole run; the generator emits
        // registry facts consistently with it (appear/vanished = a flip).
        final present = {for (final id in ids) id: rng.nextBool()};

        for (var i = 0; i < 1000; i++) {
          final event =
              _randomEvent(rng, machine.state.isIdle, ids, present, tour);
          final transition = machine.dispatch(
            event,
            targetPresent: (id) => present[id] ?? false,
          );
          _expectInvariants(transition, tour, present);
          total++;
        }
      }
      expect(total, 10000);
    });
  });
}

HintEvent _randomEvent(
  Random rng,
  bool idle,
  List<String> ids,
  Map<String, bool> present,
  HintTour tour,
) {
  String pick(List<String> pool, String fallback) =>
      pool.isEmpty ? fallback : pool[rng.nextInt(pool.length)];

  if (idle) {
    // Only HintStart leaves idle; the rest checks the no-ops.
    return switch (rng.nextInt(10)) {
      0 => const UserFinish(),
      1 => const UserSkip(),
      2 => const WaitTimeout(),
      3 => const UserPrevious(),
      4 => UserGoTo(index: rng.nextInt(tour.steps.length)),
      _ => HintStart(tour: tour),
    };
  }

  // Lifecycle: presence flip + a consistent registry event.
  if (rng.nextInt(12) == 0) {
    final id = ids[rng.nextInt(ids.length)];
    final wasPresent = present[id]!;
    present[id] = !wasPresent;
    return wasPresent
        ? TargetVanished(targetId: id)
        : TargetAppeared(targetId: id);
  }

  final appearing = [
    for (final id in ids)
      if (present[id]!) id
  ];
  final vanishing = [
    for (final id in ids)
      if (!present[id]!) id
  ];
  return switch (rng.nextInt(10)) {
    0 || 1 || 2 => TargetAppeared(targetId: pick(appearing, 'ghost')),
    3 => TargetVanished(targetId: pick(vanishing, 'ghost')),
    4 => const WaitTimeout(),
    5 => const UserNext(),
    6 => const UserPrevious(),
    7 => UserGoTo(index: rng.nextInt(tour.steps.length)),
    8 => const UserSkip(),
    _ => const UserFinish(),
  };
}

void _expectInvariants(
  HintTransition transition,
  HintTour tour,
  Map<String, bool> present,
) {
  final state = transition.state;

  switch (state) {
    case HintIdle():
      break;
    case HintWaiting(:final stepIndex):
      expect(stepIndex, inInclusiveRange(0, tour.steps.length - 1));
      break;
    case HintActive(:final stepIndex):
      expect(stepIndex, inInclusiveRange(0, tour.steps.length - 1));
      break;
  }

  for (final effect in transition.effects) {
    switch (effect) {
      case EnterStepEffect(:final stepIndex):
        expect(state, isA<HintActive>(), reason: 'EnterStep ⇒ active');
        expect(
          state.stepIndex,
          stepIndex,
          reason: 'EnterStep ⇒ the same step',
        );
        expect(
          present[tour.steps[stepIndex].targetId],
          isTrue,
          reason: 'EnterStep is only possible for a present target',
        );
        break;
      case ArmTimeoutEffect():
        expect(state, isA<HintWaiting>(), reason: 'ArmTimeout ⇒ waiting');
        break;
      case ClearTimeoutEffect():
        expect(
          state.isWaiting,
          isFalse,
          reason: 'ClearTimeout only when leaving waiting',
        );
        break;
      case AbortEffect() || FinishedEffect():
        expect(state, isA<HintIdle>(), reason: 'Abort/Finished ⇒ idle');
        break;
    }
  }
}
