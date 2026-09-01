import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/diagnostics.dart';
import 'package:hintful/engine/machine.dart';
import 'package:hintful/engine/specs.dart';

TourSpec _tour({
  int steps = 2,
  Duration stepTimeout = const Duration(seconds: 3),
}) =>
    TourSpec(
      id: 't',
      steps: [
        for (var i = 0; i < steps; i++)
          StepSpec(targetId: 'target$i', title: 'Step $i'),
      ],
      stepTimeout: stepTimeout,
    );

void expectTransition(
  TourTransition transition,
  TourState state,
  List<TourEffect> effects,
) {
  expect(transition.effects, effects, reason: 'effects');
  expect(transition.state, state, reason: 'state');
}

void main() {
  group('transition table (data → loop)', () {
    final tour = _tour();
    const idle = TourIdle();
    final waiting0 = TourWaiting(tour: tour, stepIndex: 0);
    final active0 = TourActive(tour: tour, stepIndex: 0);
    final waiting1 = TourWaiting(tour: tour, stepIndex: 1);
    final active1 = TourActive(tour: tour, stepIndex: 1);
    const arm3 = ArmTimeoutEffect(timeout: Duration(seconds: 3));

    final cases = <({
      String name,
      TourState from,
      TourEvent event,
      Map<String, bool> present,
      TourState expected,
      List<TourEffect> effects,
    })>[
      (
        name: 'start from idle → waiting(0) + timer',
        from: idle,
        event: TourStart(tour: tour),
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
        final machine = TourMachine(initialState: c.from);
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
      final tour = TourSpec(
        id: 't',
        stepTimeout: const Duration(seconds: 3),
        steps: [
          StepSpec(
            targetId: 'a',
            title: 'A',
            waitTimeout: const Duration(seconds: 7),
          ),
          StepSpec(targetId: 'b', title: 'B'),
        ],
      );
      final machine = TourMachine();

      final start = machine.dispatch(TourStart(tour: tour));
      expect(
        start.effects,
        const [ArmTimeoutEffect(timeout: Duration(seconds: 7))],
      );

      machine.dispatch(const TargetAppeared(targetId: 'a'));
      final next = machine.dispatch(const UserNext());
      expect(machine.state, TourWaiting(tour: tour, stepIndex: 1));
      expect(
        next.effects,
        const [ArmTimeoutEffect(timeout: Duration(seconds: 3))],
      );
    });
  });

  group('contracts', () {
    test('a second start over an active tour — assert in debug', () {
      final tour = _tour();
      final machine = TourMachine();
      machine.dispatch(TourStart(tour: tour));
      expect(
        () => machine.dispatch(TourStart(tour: tour)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('state equality — by tour (identity) and step', () {
      final tour = _tour();
      expect(TourWaiting(tour: tour, stepIndex: 0),
          TourWaiting(tour: tour, stepIndex: 0));
      expect(TourWaiting(tour: tour, stepIndex: 0),
          isNot(TourWaiting(tour: tour, stepIndex: 1)));
      expect(TourActive(tour: tour, stepIndex: 0),
          isNot(TourWaiting(tour: tour, stepIndex: 0)));
      expect(const TourIdle(), const TourIdle());
    });
  });

  group('fuzz: random sequences', () {
    test('10 000 events — invariants hold', () {
      final tour = _tour(steps: 3);
      final rng = Random(42);
      const ids = ['target0', 'target1', 'target2', 'ghost'];
      var total = 0;

      for (var run = 0; run < 10; run++) {
        final machine = TourMachine();
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

TourEvent _randomEvent(
  Random rng,
  bool idle,
  List<String> ids,
  Map<String, bool> present,
  TourSpec tour,
) {
  String pick(List<String> pool, String fallback) =>
      pool.isEmpty ? fallback : pool[rng.nextInt(pool.length)];

  if (idle) {
    // Only TourStart leaves idle; the rest checks the no-ops.
    return switch (rng.nextInt(8)) {
      0 => const UserFinish(),
      1 => const UserSkip(),
      2 => const WaitTimeout(),
      _ => TourStart(tour: tour),
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
  return switch (rng.nextInt(8)) {
    0 || 1 || 2 => TargetAppeared(targetId: pick(appearing, 'ghost')),
    3 => TargetVanished(targetId: pick(vanishing, 'ghost')),
    4 => const WaitTimeout(),
    5 => const UserNext(),
    6 => const UserSkip(),
    _ => const UserFinish(),
  };
}

void _expectInvariants(
  TourTransition transition,
  TourSpec tour,
  Map<String, bool> present,
) {
  final state = transition.state;

  switch (state) {
    case TourIdle():
      break;
    case TourWaiting(:final stepIndex):
      expect(stepIndex, inInclusiveRange(0, tour.steps.length - 1));
      break;
    case TourActive(:final stepIndex):
      expect(stepIndex, inInclusiveRange(0, tour.steps.length - 1));
      break;
  }

  for (final effect in transition.effects) {
    switch (effect) {
      case EnterStepEffect(:final stepIndex):
        expect(state, isA<TourActive>(), reason: 'EnterStep ⇒ active');
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
        expect(state, isA<TourWaiting>(), reason: 'ArmTimeout ⇒ waiting');
        break;
      case ClearTimeoutEffect():
        expect(
          state.isWaiting,
          isFalse,
          reason: 'ClearTimeout only when leaving waiting',
        );
        break;
      case AbortEffect() || FinishedEffect():
        expect(state, isA<TourIdle>(), reason: 'Abort/Finished ⇒ idle');
        break;
    }
  }
}
