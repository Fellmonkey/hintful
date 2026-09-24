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
sealed class HintState {
  const HintState();

  /// The running tour; null in [HintIdle].
  HintTour? get tour => switch (this) {
        HintIdle() => null,
        HintWaiting(:final tour) => tour,
        HintActive(:final tour) => tour,
      };

  /// 0-based index of the current step; null in [HintIdle].
  int? get stepIndex => switch (this) {
        HintIdle() => null,
        HintWaiting(:final stepIndex) => stepIndex,
        HintActive(:final stepIndex) => stepIndex,
      };

  /// Whether the state is [HintIdle].
  bool get isIdle => this is HintIdle;

  /// Whether the state is [HintActive].
  bool get isActive => this is HintActive;

  /// Whether the state is [HintWaiting].
  bool get isWaiting => this is HintWaiting;
}

/// No tour: zero engine widgets in the tree.
@immutable
class HintIdle extends HintState {
  /// The initial/idle state — no tour is running.
  const HintIdle();

  @override
  bool operator ==(Object other) => other is HintIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Waiting for the current step's target to appear (wait-for-target; the
/// timeout is driven by the controller via [ArmTimeoutEffect]).
@immutable
class HintWaiting extends HintState {
  /// Waiting on [stepIndex] of [tour] for its target(s) to mount.
  const HintWaiting({required this.tour, required this.stepIndex});

  @override
  final HintTour tour;
  @override
  final int stepIndex;

  /// The primary id of the step being waited for. A step may spotlight
  /// several targets ([HintStep.targetIds]) — the step becomes active only
  /// when ALL of them are present.
  String get targetId => tour.steps[stepIndex].targetId;

  @override
  bool operator ==(Object other) =>
      other is HintWaiting &&
      identical(tour, other.tour) &&
      stepIndex == other.stepIndex;

  @override
  int get hashCode =>
      Object.hash(runtimeType, identityHashCode(tour), stepIndex);

  @override
  String toString() => 'HintWaiting(${tour.id}, step $stepIndex)';
}

/// Step shown: target mounted, scrim with a hole and tooltip are active.
@immutable
class HintActive extends HintState {
  /// Step [stepIndex] of [tour] is shown (scrim + tooltip active).
  const HintActive({required this.tour, required this.stepIndex});

  @override
  final HintTour tour;
  @override
  final int stepIndex;

  /// The current step's target id (for diagnostics on abort).
  String get targetId => tour.steps[stepIndex].targetId;

  @override
  bool operator ==(Object other) =>
      other is HintActive &&
      identical(tour, other.tour) &&
      stepIndex == other.stepIndex;

  @override
  int get hashCode =>
      Object.hash(runtimeType, identityHashCode(tour), stepIndex);

  @override
  String toString() => 'HintActive(${tour.id}, step $stepIndex)';
}

// ──────────────────────────────── Events ────────────────────────────────

/// External machine inputs: user commands and registry facts.
@immutable
sealed class HintEvent {
  const HintEvent();
}

/// Start a tour — only valid from [HintIdle] (one tour at a time).
@immutable
class HintStart extends HintEvent {
  /// Wraps the [tour] to start.
  const HintStart({required this.tour});

  /// The tour to run.
  final HintTour tour;
}

/// A target registered (or re-registered) in the registry.
@immutable
class TargetAppeared extends HintEvent {
  /// Reports that [targetId] mounted in the registry.
  const TargetAppeared({required this.targetId});

  /// The registry id that appeared.
  final String targetId;
}

/// A target unregistered (disposed).
@immutable
class TargetVanished extends HintEvent {
  /// Reports that [targetId] unmounted from the registry.
  const TargetVanished({required this.targetId});

  /// The registry id that vanished.
  final String targetId;
}

/// The wait-for-target timeout elapsed (the controller generates this event
/// from the timer armed via [ArmTimeoutEffect]).
@immutable
class WaitTimeout extends HintEvent {
  /// The wait-for-target timer elapsed.
  const WaitTimeout();
}

/// Advance the tour — Next button, target tap (default), overlay tap.
@immutable
class UserNext extends HintEvent {
  /// Requests the next step (finishes the tour on the last one).
  const UserNext();
}

/// Go one step back. On the first step — a no-op (there is nothing to go
/// back to; the waiting timer is NOT re-armed, so spamming back does not
/// extend the wait).
@immutable
class UserPrevious extends HintEvent {
  /// Requests the previous step.
  const UserPrevious();
}

/// Jump to a specific step (0-based). Out-of-range: assert in debug, no-op
/// in release. Same index: a no-op (no timer reset, no re-enter).
@immutable
class UserGoTo extends HintEvent {
  /// Jumps to the 0-based [index] step.
  const UserGoTo({required this.index});

  /// 0-based index of the step to jump to.
  final int index;
}

/// Abort the tour — the user chose Skip.
@immutable
class UserSkip extends HintEvent {
  /// Requests an abort with the `userSkipped` diagnosis.
  const UserSkip();
}

/// Finish the tour normally (Done).
@immutable
class UserFinish extends HintEvent {
  /// Requests normal completion of the tour.
  const UserFinish();
}

// ──────────────────────────────── Effects ────────────────────────────────

/// Outward commands: the machine executes nothing itself — the controller
/// applies effects (timers, overlay, diagnostics). The machine's purity is
/// what makes it headlessly testable and independent of render mechanics.
@immutable
sealed class HintEffect {
  const HintEffect();
}

/// Show the step: the controller updates the overlay content (scrim + tooltip).
///
/// Emitted exactly when a step enters the active phase — the first activation
/// after waiting and every step forward.
@immutable
class EnterStepEffect extends HintEffect {
  /// Activates the step at [stepIndex] (updates the overlay content).
  const EnterStepEffect({required this.stepIndex});

  /// 0-based index of the step to show.
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
class ArmTimeoutEffect extends HintEffect {
  /// Arms the wait-for-target timer for [timeout].
  const ArmTimeoutEffect({required this.timeout});

  /// How long the target has to mount before the timeout event fires.
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
class ClearTimeoutEffect extends HintEffect {
  /// Disarms the wait-for-target timer.
  const ClearTimeoutEffect();

  @override
  bool operator ==(Object other) => other is ClearTimeoutEffect;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ClearTimeoutEffect()';
}

/// Abort the tour with a reason — `timeout` (under
/// `HintMissingTargetPolicy.abortTour`) or `userSkipped`. A spotlighted target
/// that vanishes does NOT abort: the machine returns to waiting and re-arms
/// the timeout. [detail] carries reason context (timeout duration, targetId) —
/// the controller enriches it with entity data before diagnostics.
@immutable
class AbortEffect extends HintEffect {
  /// Aborts the tour with [reason] and human-readable [detail].
  const AbortEffect({required this.reason, required this.detail});

  /// Diagnosis kind (timeout / userSkipped).
  final HintSkipReason reason;

  /// Reason context (timeout duration, target ids, …).
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is AbortEffect && other.reason == reason && other.detail == detail;

  @override
  int get hashCode => Object.hash(runtimeType, reason, detail);

  @override
  String toString() => 'AbortEffect(${reason.label}, "$detail")';
}

/// A step was skipped but the tour continues ([HintMissingTargetPolicy.skipStep]
/// on timeout: diagnosed with [reason]/[detail], then the machine advances).
/// Skipping the last step ends the tour — [FinishedEffect] arrives with it.
@immutable
class StepSkippedEffect extends HintEffect {
  /// Skips the step at [stepIndex] with [reason]/[detail]; the tour
  /// continues with the next step.
  const StepSkippedEffect({
    required this.stepIndex,
    required this.reason,
    required this.detail,
  });

  /// 0-based index of the skipped step.
  final int stepIndex;

  /// Diagnosis kind (timeout today).
  final HintSkipReason reason;

  /// Reason context for the skip.
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is StepSkippedEffect &&
      other.stepIndex == stepIndex &&
      other.reason == reason &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(runtimeType, stepIndex, reason, detail);

  @override
  String toString() =>
      'StepSkippedEffect($stepIndex, ${reason.label}, "$detail")';
}

/// Normal tour completion (last step passed or [UserFinish]).
@immutable
class FinishedEffect extends HintEffect {
  /// Completes the tour identified by [tourId].
  const FinishedEffect({required this.tourId});

  /// Id of the finished tour.
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

/// The result of a single [HintMachine.dispatch]: new state + effects.
@immutable
class HintTransition {
  /// Pairs the [state] after the dispatch with the [effects] to apply.
  const HintTransition({required this.state, required this.effects});

  /// State after the dispatch.
  final HintState state;

  /// Immutable list of effects the controller must apply.
  final List<HintEffect> effects;

  @override
  String toString() => 'HintTransition($state, $effects)';
}

/// Pure tour state machine — all transition policy in one place, zero widget
/// imports and zero knowledge of the registry/overlay.
///
/// The only external dependency is the injected `targetPresent` predicate on
/// [dispatch], by which the machine decides: advance straight to the active
/// step, or go into waiting for the target. In tests this is a presence map;
/// in the controller it is `registry.lookup(id) != null`.
class HintMachine {
  /// Creates the machine, optionally seeded with [initialState]
  /// (defaults to [HintIdle]).
  HintMachine({HintState? initialState})
      : _state = initialState ?? const HintIdle();

  HintState _state;

  /// Current state — updated by every [dispatch].
  HintState get state => _state;

  static bool _allPresent(
    bool Function(String targetId)? targetPresent,
    HintStep step,
  ) =>
      step.hasRectTarget ||
      step.targetIds.every((id) => _present(targetPresent, id));

  /// The single entry point. Returns the transition and applies it to the
  /// internal state.
  HintTransition dispatch(
    HintEvent event, {
    bool Function(String targetId)? targetPresent,
  }) {
    final current = _state;

    // One tour at a time. In debug this is a loud contract; in release a no-op.
    if (event is HintStart && !current.isIdle) {
      assert(
        false,
        "hintful: tour '${event.tour.id}' started while $current is active"
        ' — one tour at a time',
      );
      return HintTransition(state: current, effects: const <HintEffect>[]);
    }

    final effects = <HintEffect>[];
    final next = switch (current) {
      HintIdle() => _reduceIdle(event, effects),
      HintWaiting(:final tour, :final stepIndex) =>
        _reduceWaiting(tour, stepIndex, event, effects, targetPresent),
      HintActive(:final tour, :final stepIndex) =>
        _reduceActive(tour, stepIndex, event, effects, targetPresent),
    };
    _state = next;
    return HintTransition(
      state: next,
      effects: List<HintEffect>.unmodifiable(effects),
    );
  }

  HintState _reduceIdle(HintEvent event, List<HintEffect> effects) =>
      switch (event) {
        HintStart(:final tour) => tour.steps[0].hasRectTarget
            // Explicit coordinates need no waiting: enter immediately, with
            // no timeout armed (there is nothing to wait for — the overlay
            // spotlights the rect statically).
            ? _enterActive(tour, 0, effects)
            : _armWaiting(tour, 0, effects),
        _ => const HintIdle(),
      };

  /// Enter [index] as an active step (no waiting involved): used for
  /// rect-anchored starts. No timeout to clear — none was armed.
  HintState _enterActive(
    HintTour tour,
    int index,
    List<HintEffect> effects,
  ) {
    effects.add(EnterStepEffect(stepIndex: index));
    return HintActive(tour: tour, stepIndex: index);
  }

  HintState _armWaiting(HintTour tour, int index, List<HintEffect> effects) {
    effects.add(
      ArmTimeoutEffect(
        timeout: tour.steps[index].resolveTimeout(tour.stepTimeout),
      ),
    );
    return HintWaiting(tour: tour, stepIndex: index);
  }

  /// Enter [index] as an active step when all its targets are present, else
  /// arm waiting for it. [clearTimeout] clears a previously armed wait timer
  /// (transitions leaving a waiting state); skip/timeout/active paths
  /// already consumed theirs — or never armed one.
  HintState _enterOrWait(
    HintTour tour,
    int index,
    List<HintEffect> effects,
    bool Function(String targetId)? targetPresent, {
    required bool clearTimeout,
  }) {
    if (_allPresent(targetPresent, tour.steps[index])) {
      if (clearTimeout) effects.add(const ClearTimeoutEffect());
      effects.add(EnterStepEffect(stepIndex: index));
      return HintActive(tour: tour, stepIndex: index);
    }
    return _armWaiting(tour, index, effects);
  }

  HintState _reduceWaiting(
    HintTour tour,
    int index,
    HintEvent event,
    List<HintEffect> effects,
    bool Function(String targetId)? targetPresent,
  ) {
    final step = tour.steps[index];
    switch (event) {
      case TargetAppeared(:final targetId)
          when step.targetIds.contains(targetId):
        // The appeared target may be one of several: re-check ALL of the
        // step's targets before activating.
        if (_allPresent(targetPresent, step)) {
          effects.add(const ClearTimeoutEffect());
          effects.add(EnterStepEffect(stepIndex: index));
          return HintActive(tour: tour, stepIndex: index);
        }
        return HintWaiting(tour: tour, stepIndex: index);
      case UserPrevious():
        return _previous(tour, index, effects, targetPresent,
            fromWaiting: true);
      case UserGoTo(index: final toIndex):
        return _goTo(tour, index, toIndex, effects, targetPresent,
            fromWaiting: true);
      case WaitTimeout():
        final timeout = step.resolveTimeout(tour.stepTimeout);
        effects.add(const ClearTimeoutEffect());
        final missing = [
          for (final id in step.targetIds)
            if (!_present(targetPresent, id)) id,
        ];
        final detail = missing.length == 1
            ? "target '${missing.single}' did not appear within $timeout"
            : 'targets $missing did not appear within $timeout';
        if (tour.missingTargetPolicy == HintMissingTargetPolicy.skipStep) {
          effects.add(
            StepSkippedEffect(
              stepIndex: index,
              reason: HintSkipReason.timeout,
              detail: detail,
            ),
          );
          return _advanceAfterSkip(tour, index, effects, targetPresent);
        }
        effects.add(
          AbortEffect(reason: HintSkipReason.timeout, detail: detail),
        );
        return const HintIdle();
      case UserSkip():
        effects.add(const ClearTimeoutEffect());
        effects.add(
          const AbortEffect(
            reason: HintSkipReason.userSkipped,
            detail: 'user skipped',
          ),
        );
        return const HintIdle();
      case UserFinish():
        effects.add(const ClearTimeoutEffect());
        effects.add(FinishedEffect(tourId: tour.id));
        return const HintIdle();
      default:
        // Foreign targets, UserNext, HintStart — all ignored while waiting
        // (taps do not skip target-waiting). Idempotent.
        return HintWaiting(tour: tour, stepIndex: index);
    }
  }

  HintState _reduceActive(
    HintTour tour,
    int index,
    HintEvent event,
    List<HintEffect> effects,
    bool Function(String targetId)? targetPresent,
  ) {
    final step = tour.steps[index];
    switch (event) {
      case TargetVanished(:final targetId)
          when !step.hasRectTarget && step.targetIds.contains(targetId):
        // Any spotlighted target vanished on an active step (scroll
        // recycling, a collapsed tab) → re-wait for all of them instead of
        // aborting: the tour survives a transient unmount and continues when
        // the target comes back; the re-armed timeout still guards against a
        // permanent loss (a vanished target that never returns times out).
        // Rect-anchored steps are exempt: their spotlight is static
        // coordinates, registry targets (if any) are not rendered.
        effects.add(
          ArmTimeoutEffect(
            timeout: step.resolveTimeout(tour.stepTimeout),
          ),
        );
        return HintWaiting(tour: tour, stepIndex: index);
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
          return const HintIdle();
        }
        return _enterOrWait(
          tour,
          nextIndex,
          effects,
          targetPresent,
          clearTimeout: false, // active → active: no wait timer is armed
        );
      case UserSkip():
        effects.add(
          const AbortEffect(
            reason: HintSkipReason.userSkipped,
            detail: 'user skipped',
          ),
        );
        return const HintIdle();
      case UserFinish():
        effects.add(FinishedEffect(tourId: tour.id));
        return const HintIdle();
      default:
        // TargetAppeared (any), TargetVanished (foreign), WaitTimeout (no
        // timer is armed on an active step) — state stays unchanged.
        return HintActive(tour: tour, stepIndex: index);
    }
  }

  /// Back from [fromIndex]: if the previous target is present, step back
  /// immediately; otherwise wait for it (the same wait-for-target as going
  /// forward). On the first step — a no-op. [fromWaiting] decides whether
  /// leaving waiting must clear its timer.
  HintState _previous(
    HintTour tour,
    int fromIndex,
    List<HintEffect> effects,
    bool Function(String targetId)? targetPresent, {
    required bool fromWaiting,
  }) {
    if (fromIndex == 0) {
      return fromWaiting
          ? HintWaiting(tour: tour, stepIndex: 0)
          : HintActive(tour: tour, stepIndex: 0);
    }
    return _enterOrWait(
      tour,
      fromIndex - 1,
      effects,
      targetPresent,
      clearTimeout: fromWaiting,
    );
  }

  /// Jump to [toIndex] (0-based). Out-of-range: assert in debug, no-op in
  /// release. Same index: a no-op (no timer reset, no re-enter).
  /// [fromWaiting] decides whether leaving waiting must clear its timer.
  HintState _goTo(
    HintTour tour,
    int fromIndex,
    int toIndex,
    List<HintEffect> effects,
    bool Function(String targetId)? targetPresent, {
    required bool fromWaiting,
  }) {
    final stay = fromWaiting
        ? HintWaiting(tour: tour, stepIndex: fromIndex)
        : HintActive(tour: tour, stepIndex: fromIndex);
    if (toIndex == fromIndex) return stay;
    assert(
      toIndex >= 0 && toIndex < tour.steps.length,
      "hintful: goTo($toIndex) out of range 0..${tour.steps.length - 1}",
    );
    if (toIndex < 0 || toIndex >= tour.steps.length) return stay;
    return _enterOrWait(
      tour,
      toIndex,
      effects,
      targetPresent,
      clearTimeout: fromWaiting,
    );
  }

  /// Continue after a skipped missing step: activate the next step when all
  /// its targets are present, else wait for it. Past the last step — finish
  /// (the skip itself is already diagnosed via [StepSkippedEffect]).
  HintState _advanceAfterSkip(
    HintTour tour,
    int fromIndex,
    List<HintEffect> effects,
    bool Function(String targetId)? targetPresent,
  ) {
    final nextIndex = fromIndex + 1;
    if (nextIndex >= tour.steps.length) {
      effects.add(FinishedEffect(tourId: tour.id));
      return const HintIdle();
    }
    return _enterOrWait(
      tour,
      nextIndex,
      effects,
      targetPresent,
      // Skip/timeout paths already consumed their wait timer.
      clearTimeout: false,
    );
  }

  static bool _present(
    bool Function(String targetId)? targetPresent,
    String targetId,
  ) =>
      targetPresent?.call(targetId) ?? false;
}
