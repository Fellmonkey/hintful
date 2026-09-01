import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'specs.dart';

// ───────────────────────────────── States ────────────────────────────────

/// Observable tour state.
///
/// Three states deliberately: `waiting` ≠ `active`. A deferred target
/// (lazy tab, not-yet-mounted widget) means "the tour started but there is
/// nothing to spotlight" — a separate phase with its own timeout and UX
/// (scrim without a hole, "preparing"). Phases must not be merged: otherwise
/// "show" and "wait" are indistinguishable in tests and diagnostics.
@immutable
sealed class TourState {
  const TourState();

  TourSpec? get tour => switch (this) {
        TourIdle() => null,
        TourWaiting(:final tour) => tour,
        TourActive(:final tour) => tour,
      };

  int? get stepIndex => switch (this) {
        TourIdle() => null,
        TourWaiting(:final stepIndex) => stepIndex,
        TourActive(:final stepIndex) => stepIndex,
      };

  bool get isIdle => this is TourIdle;
  bool get isActive => this is TourActive;
  bool get isWaiting => this is TourWaiting;
}

/// No tour: zero engine widgets in the tree.
@immutable
class TourIdle extends TourState {
  const TourIdle();

  @override
  bool operator ==(Object other) => other is TourIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Waiting for the current step's target to appear (wait-for-target; the
/// timeout is driven by the controller via [ArmTimeoutEffect]).
@immutable
class TourWaiting extends TourState {
  const TourWaiting({required this.tour, required this.stepIndex});

  @override
  final TourSpec tour;
  @override
  final int stepIndex;

  /// The id being waited for on this step.
  String get targetId => tour.steps[stepIndex].targetId;

  @override
  bool operator ==(Object other) =>
      other is TourWaiting &&
      identical(tour, other.tour) &&
      stepIndex == other.stepIndex;

  @override
  int get hashCode =>
      Object.hash(runtimeType, identityHashCode(tour), stepIndex);

  @override
  String toString() => 'TourWaiting(${tour.id}, step $stepIndex)';
}

/// Step shown: target mounted, scrim with a hole and tooltip are active.
@immutable
class TourActive extends TourState {
  const TourActive({required this.tour, required this.stepIndex});

  @override
  final TourSpec tour;
  @override
  final int stepIndex;

  /// The current step's target id (for diagnostics on abort).
  String get targetId => tour.steps[stepIndex].targetId;

  @override
  bool operator ==(Object other) =>
      other is TourActive &&
      identical(tour, other.tour) &&
      stepIndex == other.stepIndex;

  @override
  int get hashCode =>
      Object.hash(runtimeType, identityHashCode(tour), stepIndex);

  @override
  String toString() => 'TourActive(${tour.id}, step $stepIndex)';
}

// ──────────────────────────────── Events ────────────────────────────────

/// External machine inputs: user commands and registry facts.
@immutable
sealed class TourEvent {
  const TourEvent();
}

@immutable
class TourStart extends TourEvent {
  const TourStart({required this.tour});

  final TourSpec tour;
}

/// A target registered (or re-registered) in the registry.
@immutable
class TargetAppeared extends TourEvent {
  const TargetAppeared({required this.targetId});

  final String targetId;
}

/// A target unregistered (disposed).
@immutable
class TargetVanished extends TourEvent {
  const TargetVanished({required this.targetId});

  final String targetId;
}

/// The wait-for-target timeout elapsed (the controller generates this event
/// from the timer armed via [ArmTimeoutEffect]).
@immutable
class WaitTimeout extends TourEvent {
  const WaitTimeout();
}

@immutable
class UserNext extends TourEvent {
  const UserNext();
}

/// Go one step back. On the first step — a no-op (there is nothing to go
/// back to; the waiting timer is NOT re-armed, so spamming back does not
/// extend the wait).
@immutable
class UserPrevious extends TourEvent {
  const UserPrevious();
}

/// Jump to a specific step (0-based). Out-of-range: assert in debug, no-op
/// in release. Same index: a no-op (no timer reset, no re-enter).
@immutable
class UserGoTo extends TourEvent {
  const UserGoTo({required this.index});

  final int index;
}

@immutable
class UserSkip extends TourEvent {
  const UserSkip();
}

@immutable
class UserFinish extends TourEvent {
  const UserFinish();
}

// ──────────────────────────────── Effects ────────────────────────────────

/// Outward commands: the machine executes nothing itself — the controller
/// applies effects (timers, overlay, diagnostics). The machine's purity is
/// what makes it headlessly testable and independent of render mechanics.
@immutable
sealed class TourEffect {
  const TourEffect();
}

/// Show the step: the controller updates the overlay content (scrim + tooltip).
///
/// Emitted exactly when a step enters the active phase — the first activation
/// after waiting and every step forward.
@immutable
class EnterStepEffect extends TourEffect {
  const EnterStepEffect({required this.stepIndex});

  final int stepIndex;

  @override
  bool operator ==(Object other) =>
      other is EnterStepEffect && other.stepIndex == stepIndex;

  @override
  int get hashCode => Object.hash(runtimeType, stepIndex);

  @override
  String toString() => 'EnterStepEffect($stepIndex)';
}

/// Arm the wait-for-target timer; emitted exactly when entering waiting.
@immutable
class ArmTimeoutEffect extends TourEffect {
  const ArmTimeoutEffect({required this.timeout});

  final Duration timeout;

  @override
  bool operator ==(Object other) =>
      other is ArmTimeoutEffect && other.timeout == timeout;

  @override
  int get hashCode => Object.hash(runtimeType, timeout);

  @override
  String toString() => 'ArmTimeoutEffect($timeout)';
}

/// Clear the timer; emitted when leaving waiting (into active or idle).
@immutable
class ClearTimeoutEffect extends TourEffect {
  const ClearTimeoutEffect();

  @override
  bool operator ==(Object other) => other is ClearTimeoutEffect;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ClearTimeoutEffect()';
}

/// Abort the tour with a reason (timeout, skip, target vanished,
/// unknown-target). [detail] carries reason context (timeout duration,
/// targetId) — the controller enriches it with entity data before
/// diagnostics.
@immutable
class AbortEffect extends TourEffect {
  const AbortEffect({required this.reason, required this.detail});

  final HintSkipReason reason;
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is AbortEffect && other.reason == reason && other.detail == detail;

  @override
  int get hashCode => Object.hash(runtimeType, reason, detail);

  @override
  String toString() => 'AbortEffect(${reason.label}, "$detail")';
}

/// Normal tour completion (last step passed or [UserFinish]).
@immutable
class FinishedEffect extends TourEffect {
  const FinishedEffect({required this.tourId});

  final String tourId;

  @override
  bool operator ==(Object other) =>
      other is FinishedEffect && other.tourId == tourId;

  @override
  int get hashCode => Object.hash(runtimeType, tourId);

  @override
  String toString() => 'FinishedEffect($tourId)';
}

// ───────────────────────── Transition and machine ────────────────────────

/// The result of a single [TourMachine.dispatch]: new state + effects.
@immutable
class TourTransition {
  const TourTransition({required this.state, required this.effects});

  final TourState state;

  /// Immutable list of effects the controller must apply.
  final List<TourEffect> effects;

  @override
  String toString() => 'TourTransition($state, $effects)';
}

/// Pure tour state machine — all transition policy in one place, zero widget
/// imports and zero knowledge of the registry/overlay.
///
/// The only external dependency is the injected `targetPresent` predicate on
/// [dispatch], by which the machine decides: advance straight to the active
/// step, or go into waiting for the target. In tests this is a presence map;
/// in the controller it is `registry.lookup(id) != null`.
class TourMachine {
  TourMachine({TourState? initialState})
      : _state = initialState ?? const TourIdle();

  TourState _state;
  TourState get state => _state;

  static String _targetIdOf(TourSpec tour, int index) =>
      tour.steps[index].targetId;

  /// The single entry point. Returns the transition and applies it to the
  /// internal state.
  TourTransition dispatch(
    TourEvent event, {
    bool Function(String targetId)? targetPresent,
  }) {
    final current = _state;

    // One tour at a time. In debug this is a loud contract; in release a no-op.
    if (event is TourStart && !current.isIdle) {
      assert(
        false,
        "hintful: tour '${event.tour.id}' started while $current is active"
        ' — one tour at a time',
      );
      return TourTransition(state: current, effects: const <TourEffect>[]);
    }

    final effects = <TourEffect>[];
    final next = switch (current) {
      TourIdle() => _reduceIdle(event, effects),
      TourWaiting(:final tour, :final stepIndex) =>
        _reduceWaiting(tour, stepIndex, event, effects, targetPresent),
      TourActive(:final tour, :final stepIndex) =>
        _reduceActive(tour, stepIndex, event, effects, targetPresent),
    };
    _state = next;
    return TourTransition(
      state: next,
      effects: List<TourEffect>.unmodifiable(effects),
    );
  }

  TourState _reduceIdle(TourEvent event, List<TourEffect> effects) =>
      switch (event) {
        TourStart(:final tour) => _armWaiting(tour, 0, effects),
        _ => const TourIdle(),
      };

  TourState _armWaiting(TourSpec tour, int index, List<TourEffect> effects) {
    effects.add(
      ArmTimeoutEffect(
        timeout: tour.steps[index].resolveTimeout(tour.stepTimeout),
      ),
    );
    return TourWaiting(tour: tour, stepIndex: index);
  }

  TourState _reduceWaiting(
    TourSpec tour,
    int index,
    TourEvent event,
    List<TourEffect> effects,
    bool Function(String targetId)? targetPresent,
  ) {
    final needed = _targetIdOf(tour, index);
    switch (event) {
      case TargetAppeared(:final targetId) when targetId == needed:
        effects.add(const ClearTimeoutEffect());
        effects.add(EnterStepEffect(stepIndex: index));
        return TourActive(tour: tour, stepIndex: index);
      case UserPrevious():
        return _previous(tour, index, effects, targetPresent,
            fromWaiting: true);
      case UserGoTo(index: final toIndex):
        return _goTo(tour, index, toIndex, effects, targetPresent,
            fromWaiting: true);
      case WaitTimeout():
        final timeout = tour.steps[index].resolveTimeout(tour.stepTimeout);
        effects.add(const ClearTimeoutEffect());
        effects.add(
          AbortEffect(
            reason: HintSkipReason.timeout,
            detail: "target '$needed' did not appear within $timeout",
          ),
        );
        return const TourIdle();
      case UserSkip():
        effects.add(const ClearTimeoutEffect());
        effects.add(
          const AbortEffect(
            reason: HintSkipReason.userSkipped,
            detail: 'user skipped',
          ),
        );
        return const TourIdle();
      case UserFinish():
        effects.add(const ClearTimeoutEffect());
        effects.add(FinishedEffect(tourId: tour.id));
        return const TourIdle();
      default:
        // Foreign targets, UserNext, TourStart — all ignored while waiting
        // (taps do not skip target-waiting). Idempotent.
        return TourWaiting(tour: tour, stepIndex: index);
    }
  }

  TourState _reduceActive(
    TourSpec tour,
    int index,
    TourEvent event,
    List<TourEffect> effects,
    bool Function(String targetId)? targetPresent,
  ) {
    final currentTarget = _targetIdOf(tour, index);
    switch (event) {
      case TargetVanished(:final targetId) when targetId == currentTarget:
        // The target vanished on an active step (e.g. the user collapsed a
        // tab) → abort. Re-waiting instead of aborting is follow-up work.
        effects.add(
          AbortEffect(
            reason: HintSkipReason.targetUnmountedDuringStep,
            detail: "target '$currentTarget' unmounted during step"
                ' ${index + 1}',
          ),
        );
        return const TourIdle();
      case UserPrevious():
        return _previous(tour, index, effects, targetPresent,
            fromWaiting: false);
      case UserGoTo(index: final toIndex):
        return _goTo(tour, index, toIndex, effects, targetPresent,
            fromWaiting: false);
      case UserNext():
        final nextIndex = index + 1;
        if (nextIndex >= tour.steps.length) {
          effects.add(FinishedEffect(tourId: tour.id));
          return const TourIdle();
        }
        if (_present(targetPresent, _targetIdOf(tour, nextIndex))) {
          effects.add(EnterStepEffect(stepIndex: nextIndex));
          return TourActive(tour: tour, stepIndex: nextIndex);
        }
        return _armWaiting(tour, nextIndex, effects);
      case UserSkip():
        effects.add(
          const AbortEffect(
            reason: HintSkipReason.userSkipped,
            detail: 'user skipped',
          ),
        );
        return const TourIdle();
      case UserFinish():
        effects.add(FinishedEffect(tourId: tour.id));
        return const TourIdle();
      default:
        // TargetAppeared (any), TargetVanished (foreign), WaitTimeout (no
        // timer is armed on an active step) — state stays unchanged.
        return TourActive(tour: tour, stepIndex: index);
    }
  }

  /// Back from [fromIndex]: if the previous target is present, step back
  /// immediately; otherwise wait for it (the same wait-for-target as going
  /// forward). On the first step — a no-op. [fromWaiting] decides whether
  /// leaving waiting must clear its timer.
  TourState _previous(
    TourSpec tour,
    int fromIndex,
    List<TourEffect> effects,
    bool Function(String targetId)? targetPresent, {
    required bool fromWaiting,
  }) {
    if (fromIndex == 0) {
      return fromWaiting
          ? TourWaiting(tour: tour, stepIndex: 0)
          : TourActive(tour: tour, stepIndex: 0);
    }
    final prev = fromIndex - 1;
    if (_present(targetPresent, _targetIdOf(tour, prev))) {
      if (fromWaiting) effects.add(const ClearTimeoutEffect());
      effects.add(EnterStepEffect(stepIndex: prev));
      return TourActive(tour: tour, stepIndex: prev);
    }
    return _armWaiting(tour, prev, effects);
  }

  /// Jump to [toIndex] (0-based). Out-of-range: assert in debug, no-op in
  /// release. Same index: a no-op (no timer reset, no re-enter).
  /// [fromWaiting] decides whether leaving waiting must clear its timer.
  TourState _goTo(
    TourSpec tour,
    int fromIndex,
    int toIndex,
    List<TourEffect> effects,
    bool Function(String targetId)? targetPresent, {
    required bool fromWaiting,
  }) {
    final stay = fromWaiting
        ? TourWaiting(tour: tour, stepIndex: fromIndex)
        : TourActive(tour: tour, stepIndex: fromIndex);
    if (toIndex == fromIndex) return stay;
    assert(
      toIndex >= 0 && toIndex < tour.steps.length,
      "hintful: goTo($toIndex) out of range 0..${tour.steps.length - 1}",
    );
    if (toIndex < 0 || toIndex >= tour.steps.length) return stay;
    if (_present(targetPresent, _targetIdOf(tour, toIndex))) {
      if (fromWaiting) effects.add(const ClearTimeoutEffect());
      effects.add(EnterStepEffect(stepIndex: toIndex));
      return TourActive(tour: tour, stepIndex: toIndex);
    }
    return _armWaiting(tour, toIndex, effects);
  }

  static bool _present(
    bool Function(String targetId)? targetPresent,
    String targetId,
  ) =>
      targetPresent?.call(targetId) ?? false;
}
