import 'dart:async';

import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'machine.dart';
import 'registry.dart';
import 'specs.dart';

/// Overlay host — the contract of tour render mechanics.
///
/// The controller does not know what the overlay looks like: it only asks to
/// show the machine's current state and hide it on completion. The
/// implementation is `HintOverlayEngine`. In headless runs the host is absent
/// (`overlayHost: null`) and tours run without rendering: the machine, timers
/// and diagnostics always work — this is what makes the engine a testable
/// artifact.
abstract class HintOverlayHost {
  /// Show/update the UI for [state] (waiting — scrim without a hole, active —
  /// hole + tooltip); on [HintIdle] — remove the overlay.
  void update(HintState state);

  /// Release host resources (entry, timers, listeners).
  void dispose();
}

/// A sealed-off step: it references a targetId absent from the registry but
/// with close candidates (distance ≤ 2) — almost certainly a typo.
/// [typoId] is the offending id itself (a step may spotlight several
/// targets — [HintStep.targetIds]); the step is skipped wholesale.
typedef UnknownHintTarget = ({
  HintStep step,
  int index,
  String typoId,
  List<String> candidates
});

/// Classifies a tour's steps by their target ids ([HintStep.targetIds] —
/// extras included) against the registry's known ids.
///
/// Typo policy:
/// - a step referencing an id **with candidates** (similar ids exist) — a
///   typo: fails loudly in debug, is skipped in release (waiting for it is
///   pointless);
/// - a step whose ids are all known or **without candidates** — a
///   legitimate deferred target: wait, the timeout produces its own
///   diagnosis;
/// - an id whose only difference from a candidate **is digits**
///   (`target1`/`target2` sequences) — also deferred: numeric suffixes are
///   naming, not typos; otherwise every following step in a sequence would
///   look like a typo of the previous one.
/// A pure function: tested directly, applied by the controller.
@visibleForTesting
({List<HintStep> deferred, List<UnknownHintTarget> typos}) classifyStepTargets(
    HintTour tour, Set<String> knownIds) {
  final deferred = <HintStep>[];
  final typos = <UnknownHintTarget>[];
  for (var i = 0; i < tour.steps.length; i++) {
    final step = tour.steps[i];
    if (step.targetIds.every(knownIds.contains)) continue; // all known
    String? typoId;
    List<String>? candidates;
    for (final id in step.targetIds) {
      if (knownIds.contains(id)) continue;
      final c = closestTargetIds(id, knownIds);
      if (c.isEmpty || _differsOnlyInDigits(id, c.first)) continue;
      typoId = id;
      candidates = c;
      break;
    }
    if (typoId == null) {
      deferred.add(step);
    } else {
      typos.add((
        step: step,
        index: i,
        typoId: typoId,
        candidates: candidates!,
      ));
    }
  }
  return (deferred: deferred, typos: typos);
}

/// true if the ids match after removing all digits — meaning they differ only
/// in numeric suffixes (`flag1` vs `flag2`), which is naming, not a typo.
bool _differsOnlyInDigits(String a, String b) {
  final digits = RegExp(r'\d');
  return a.replaceAll(digits, '') == b.replaceAll(digits, '');
}

/// The single public point for controlling a tour.
///
/// Owns the machine, registry, timer and (optionally) the overlay. State is
/// published as a [ValueListenable] — the vanilla Flutter default without any
/// state-management dependency; adapters build on this same contract. No
/// contexts/singletons are stored — the ValueNotifier state survives
/// hot-reload and an open overlay is not reset (hot-reload friendly by
/// construction).
class HintController implements HintActions {
  /// [registry] defaults to the default singleton (zero-config).
  /// [diagnostics] defaults to `DebugPrintDiagnostics`, but only in debug
  /// builds: in release the diagnostics cost is zero, reasons go to the
  /// callback if the user supplies a handler.
  /// [overlayHostBuilder] is a lazy factory for the render mechanics and
  /// receives the controller itself (the engine needs the input back-channel:
  /// next/skip/finish); null = headless.
  HintController({
    HintTargetRegistry? registry,
    HintDiagnosticsHandler? diagnostics,
    HintOverlayHost Function(HintController)? overlayHostBuilder,
  })  : _registry = registry ?? HintTargetRegistry.defaultInstance,
        _diagnostics =
            diagnostics ?? (kDebugMode ? const DebugPrintDiagnostics() : null),
        _overlayHostBuilder = overlayHostBuilder {
    // A listener, not a slot: other subsystems subscribe the same way, and
    // several controllers on one registry no longer overwrite each other.
    _registry.addListener(_onRegistryChanged);
    _lastKnownIds = _registry.ids;
  }

  final HintTargetRegistry _registry;
  final HintDiagnosticsHandler? _diagnostics;
  final HintOverlayHost Function(HintController)? _overlayHostBuilder;
  HintOverlayHost? _builtHost;

  final HintMachine _machine = HintMachine();
  final ValueNotifier<HintState> _stateNotifier =
      ValueNotifier<HintState>(const HintIdle());

  Timer? _timer;
  Set<String> _lastKnownIds = const {};
  bool _registrySyncScheduled = false;
  bool _disposed = false;

  /// Observable tour state.
  ValueListenable<HintState> get state => _stateNotifier;

  HintState get currentState => _stateNotifier.value;

  /// Start a tour: typo validation → machine → seeding of already-mounted
  /// targets. The wait-for-target timer is armed by a machine effect.
  ///
  /// Async deliberately: (1) the typo AssertionError goes into the Future
  /// (loud failure in debug from `expectLater`) instead of being thrown in
  /// the middle of someone's build; (2) later `start` will await fetching a
  /// server-driven tour — the signature is already ready and won't need a
  /// breaking change.
  Future<void> start(HintTour tour) async {
    assert(
      _machine.state.isIdle,
      "hintful: start('${tour.id}') while ${_machine.state} is active"
      ' — one tour at a time',
    );
    assert(
      tour.duplicateTargetIds.isEmpty,
      "hintful: tour '${tour.id}' has duplicate step targetIds:"
      ' ${tour.duplicateTargetIds.join(', ')}',
    );

    final classification = classifyStepTargets(
      tour,
      Set<String>.of(_registry.ids),
    );
    if (classification.typos.isNotEmpty) {
      final message = _describeTypos(tour, classification.typos);
      assert(false, message); // debug: loud failure with candidates
      tour = _withoutTypoSteps(tour, classification.typos); // release: skip
      if (tour.steps.isEmpty) return; // nothing to show
    }

    _dispatch(HintStart(tour: tour));

    // Already-mounted targets will not fire onChange (the registry did not
    // change) — seed them synchronously, otherwise waiting(0) would spin
    // forever.
    for (final id in _registry.ids) {
      _dispatch(TargetAppeared(targetId: id));
    }
    _lastKnownIds = _registry.ids;
  }

  /// Fast path for a single hint: a one-step tour without HintTour ceremony.
  ///
  /// Equivalent to `start(HintTour(id: 'hint:<targetId>', steps: [step]))` —
  /// the same wait-for-target, timeout, typo validation and diagnostics as a
  /// full tour. One tour at a time: calling it during an active tour is an
  /// assert (same as [start]).
  Future<void> showHint(HintStep step) => start(
        HintTour(id: 'hint:${step.targetId}', steps: [step]),
      );

  @override
  void next() => _dispatch(const UserNext());

  @override
  void previous() => _dispatch(const UserPrevious());

  /// Jump to a specific step (0-based).
  ///
  /// Out-of-range: assert in debug (a loud tour-authoring error), no-op in
  /// release. In idle (no active tour) — a no-op.
  void goTo(int index) {
    final steps = _machine.state.tour?.steps;
    if (steps == null) return; // no active tour
    assert(
      index >= 0 && index < steps.length,
      "hintful: goTo($index) out of range 0..${steps.length - 1}",
    );
    _dispatch(UserGoTo(index: index));
  }

  @override
  void skip() => _dispatch(const UserSkip());

  @override
  void finish() => _dispatch(const UserFinish());

  /// Idempotent — a second dispose is a no-op (used in-body and via
  /// `addTearDown`).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _registry.removeListener(_onRegistryChanged);
    _builtHost?.dispose();
    _stateNotifier.dispose();
  }

  // ─────────────────────────── internals ───────────────────────────

  /// Registry changes can arrive synchronously from initState (during some
  /// widget's build) — defer processing to a microtask so ValueNotifier
  /// listeners are not notified mid-frame-build.
  void _onRegistryChanged() {
    if (_registrySyncScheduled) return;
    _registrySyncScheduled = true;
    scheduleMicrotask(() {
      _registrySyncScheduled = false;
      _syncRegistry();
    });
  }

  /// Snapshot diff: registration → appeared, removal → vanished.
  void _syncRegistry() {
    // A microtask may have been scheduled before dispose — dispatching after
    // it would write into a destroyed notifier.
    if (_disposed) return;
    final current = _registry.ids;
    final previous = _lastKnownIds;
    for (final id in current.difference(previous)) {
      _dispatch(TargetAppeared(targetId: id));
    }
    for (final id in previous.difference(current)) {
      _dispatch(TargetVanished(targetId: id));
    }
    _lastKnownIds = current;
  }

  void _dispatch(HintEvent event) {
    final before = _machine.state;
    final transition = _machine.dispatch(
      event,
      targetPresent: (id) => _registry.lookup(id) != null,
    );
    _applyEffects(transition, before);
    _stateNotifier.value = transition.state;
    _hostFor(transition.state)?.update(transition.state);
    if (transition.state.isIdle) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Lazily builds the host at the first non-idle state: the builder is not
  /// called for headless runs and does not create an overlay without need.
  HintOverlayHost? _hostFor(HintState state) {
    if (_builtHost != null) return _builtHost;
    if (state.isIdle || _overlayHostBuilder == null) return null;
    return _builtHost = _overlayHostBuilder!(this);
  }

  void _applyEffects(HintTransition transition, HintState before) {
    for (final effect in transition.effects) {
      switch (effect) {
        case ArmTimeoutEffect(:final timeout):
          _timer?.cancel();
          _timer = Timer(timeout, () => _dispatch(const WaitTimeout()));
          break;
        case ClearTimeoutEffect():
          _timer?.cancel();
          _timer = null;
          break;
        case AbortEffect(:final reason, :final detail):
          _reportAbort(before, reason, detail);
          break;
        case EnterStepEffect():
        case FinishedEffect():
          // Rendering follows the state (host.update); finish is not
          // diagnosed.
          break;
      }
    }
  }

  /// An abort carries the "before" context: after the transition the machine
  /// is already idle, and tourId/stepIndex/targetId would have to be
  /// reconstructed from nothing.
  void _reportAbort(HintState before, HintSkipReason reason, String detail) {
    final tourId = before.tour?.id ?? '?';
    final stepIndex = before.stepIndex ?? 0;
    final targetId = switch (before) {
      HintWaiting(:final targetId) => targetId,
      HintActive(:final targetId) => targetId,
      _ => '?',
    };
    _diagnostics?.onHintSkipped(tourId, stepIndex, targetId, reason, detail);
  }

  String _describeTypos(HintTour tour, List<UnknownHintTarget> typos) {
    final parts = typos.map((t) {
      final candidates = t.candidates.join(', ');
      return "step ${t.index + 1} references unknown targetId '${t.typoId}'"
          '; closest: $candidates';
    }).join('; ');
    return "hintful: tour '${tour.id}' — $parts";
  }

  /// Release-path typo handling: typo steps are skipped, the tour continues.
  HintTour _withoutTypoSteps(HintTour tour, List<UnknownHintTarget> typos) {
    for (final t in typos) {
      _diagnostics?.onHintSkipped(
        tour.id,
        t.index,
        t.typoId,
        HintSkipReason.unknownTarget,
        'no valid target; closest: ${t.candidates.join(', ')}; step skipped',
      );
    }
    final removed = typos.map((t) => t.step).toSet();
    final kept = tour.steps.where((step) => !removed.contains(step)).toList();
    return HintTour(
      id: tour.id,
      steps: kept,
      stepTimeout: tour.stepTimeout,
      disableBackButton: tour.disableBackButton,
    );
  }
}
