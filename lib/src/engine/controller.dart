import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'diagnostics.dart';
import 'machine.dart';
import 'overlay/overlay_engine.dart' show defaultOverlayHost;
import 'registry.dart';
import 'specs.dart';
import 'store.dart';

/// Overlay host — the contract of tour render mechanics.
///
/// The controller does not know what the overlay looks like: it only asks to
/// show the machine's current state and hide it on completion. The
/// implementation is `HintOverlayEngine`. In headless runs
/// (`HintController.test()` — the `@visibleForTesting` factory) the host is
/// absent and tours run without rendering: the machine, timers and
/// diagnostics always work — this is what makes the engine a testable
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

/// Pure function — tested directly, applied by `showTour` on every tour start.
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
/// Owns the machine, registry, timer and (when rendering) the overlay. State is
/// published as a [ValueListenable] — the vanilla Flutter default without any
/// state-management dependency; app-side adapters build on this same
/// contract. No contexts/singletons are stored — the ValueNotifier state
/// survives hot-reload and an open overlay is not reset (hot-reload friendly
/// by construction).
class HintController implements HintActions {
  /// [registry] defaults to the default singleton (zero-config) — the same
  /// instance the default overlay host renders from ([registry] getter: one
  /// source of truth, the wait logic and the rendering cannot desync).
  /// [diagnostics] is a plain callback (see [HintDiagnosticsHandler]); debug
  /// builds print the same event as one line **before** invoking it, so a
  /// custom handler never silences the console; in release the callback runs
  /// alone, or is absent — zero cost.
  /// The store read by [tryShowTour] and `showHintTourOffer` is app-wide:
  /// configure it once with `Hintful.configure(store: ...)`. Without one,
  /// show-once works for this run through a session-scoped
  /// [InMemoryHintStore] (a one-time warning is printed) — configure a
  /// persistent store for real once-per-version semantics.
  ///
  /// `HintController()` renders out of the box: the default engine wiring
  /// runs (the host is built lazily on the first non-idle state).
  HintController({
    HintTargetRegistry? registry,
    HintDiagnosticsHandler? diagnostics,
    String? scopePrefix,
  }) : this._(
          registry: registry,
          diagnostics: diagnostics,
          scopePrefix: scopePrefix,
          store: null,
          overlayHostBuilder: defaultOverlayHost,
        );

  /// Test seam — not part of the public contract. Runs headless: the whole
  /// machine, timers and diagnostics with no render mechanics. [store]
  /// overrides the app-wide `Hintful` store for this one controller. The
  /// production path is the unnamed constructor plus `Hintful.configure`.
  @visibleForTesting
  HintController.test({
    HintTargetRegistry? registry,
    HintDiagnosticsHandler? diagnostics,
    String? scopePrefix,
    HintStore? store,
  }) : this._(
          registry: registry,
          diagnostics: diagnostics,
          scopePrefix: scopePrefix,
          store: store,
          overlayHostBuilder: null,
        );

  /// The single initializer behind [HintController] and [HintController.test]:
  /// resolves the registry default, composes
  /// the diagnostics handler and wires the registry listener.
  HintController._({
    HintTargetRegistry? registry,
    HintDiagnosticsHandler? diagnostics,
    this.scopePrefix,
    HintStore? store,
    required HintOverlayHost Function(HintController)? overlayHostBuilder,
  })  : _registry = registry ?? HintTargetRegistry.defaultInstance,
        _diagnostics = _composeDiagnostics(diagnostics),
        _storeOverride = store,
        _overlayHostBuilder = overlayHostBuilder {
    _init();
  }

  /// The user callback composed with the debug print: in debug builds the
  /// one-line diagnosis always fires first, then the callback when one is
  /// attached; in release only the callback survives (or nothing).
  static HintDiagnosticsHandler? _composeDiagnostics(
    HintDiagnosticsHandler? user,
  ) {
    if (!kDebugMode) return user;
    if (user == null) return debugPrintHintSkip;
    return (event) {
      debugPrintHintSkip(event);
      user(event);
    };
  }

  void _init() {
    // A listener, not a slot: other subsystems subscribe the same way, and
    // several controllers on one registry no longer overwrite each other.
    _registry.addListener(_onRegistryChanged);
    // The id set exists only while a tour runs (registry diffing). Held
    // while idle it would retain the registry's ids between tours (zero-idle
    // cost) — [showTour] reseeds and rebuilds it.
    _lastKnownIds = const {};
  }

  final HintTargetRegistry _registry;
  final HintDiagnosticsHandler? _diagnostics;
  final HintOverlayHost Function(HintController)? _overlayHostBuilder;

  /// Per-controller store override (tests / [HintController.test]); null —
  /// the app-wide [Hintful.store] (or the session fallback) is used.
  final HintStore? _storeOverride;

  /// The registry this controller's wait logic runs over — and the registry
  /// the default overlay host ([defaultOverlayHost]) renders from. Set once
  /// via the constructor; never desynced from the rendering.
  ///
  /// Pairing rule: when you pass a custom [registry] here, every
  /// `HintTarget` (or `withHint`) in the scene must receive
  /// the same instance — a controller watching a registry the
  /// targets do not register into diagnoses every step as
  /// `timeout`/`unknownTarget`. Omit the parameter on both sides to
  /// share [HintTargetRegistry.defaultInstance] (zero-config).
  HintTargetRegistry get registry => _registry;

  /// The handler this controller reports failed shows to — the composed
  /// handler (your callback, with the debug print running first in debug
  /// builds). Also handed to the default overlay host — engine-side overlay
  /// failures (`overlayUnavailable`) go through the same channel.
  HintDiagnosticsHandler? get diagnostics => _diagnostics;
  HintOverlayHost? _builtHost;

  /// The one-time misconfiguration warning of [store]. Deliberately **not**
  /// [kDebugMode]-gated (unlike the diagnostics sink's debug print): a
  /// storeless release build re-shows the hint on every launch, and this line
  /// is the only place that says so.
  static const String _noStoreWarning =
      'hintful: no HintStore configured — using an in-memory session store. '
      'Show-once state lives for this run only, so a release build shows the '
      'same hint on every launch. Persist it with '
      'Hintful.configure(store: CallbackHintStore(read: ..., write: ...)) or '
      'the hintful_prefs package.';

  /// The store show-once paths use: the test override when set, else the
  /// app-wide [Hintful.store], else the shared session [InMemoryHintStore]
  /// ([Hintful.sessionStore]). The first time that fallback is taken in this
  /// run, [_noStoreWarning] prints. Never null — call sites do not need a
  /// null-check.
  ///
  /// Internal: configure the store app-wide with `Hintful.configure`; this
  /// getter exists for the package's own offer dialog and tests.
  @internal
  HintStore get store {
    final override = _storeOverride;
    if (override != null) return override;
    final configured = Hintful.store;
    if (configured != null) return configured;
    if (!_warnedNoStore) {
      _warnedNoStore = true;
      debugPrint(_noStoreWarning);
    }
    return Hintful.sessionStore;
  }

  /// Scope: which registry ids belong to this controller's screen.
  ///
  /// Screens mounted at once (tabs, split-view) share
  /// [HintTargetRegistry.defaultInstance]: without a scope a controller sees
  /// foreign ids — a step can activate on another screen's target, and typo
  /// candidates can false-fire. One controller per screen with ids prefixed
  /// per screen (`scopePrefix: 'greenhouse-'` / `'spread-'`); null — no
  /// scoping (global).
  final String? scopePrefix;

  final HintMachine _machine = HintMachine();
  final ValueNotifier<HintState> _stateNotifier =
      ValueNotifier<HintState>(const HintIdle());

  Timer? _timer;
  Set<String> _lastKnownIds = const {};
  bool _registrySyncScheduled = false;
  bool _disposed = false;
  bool _warnedNoStore = false;

  /// The step visit that received `onStepEnter` and is still open
  /// (`onStepExit` not yet fired). null — no open visit.
  ({HintTour tour, int index})? _hookedVisit;

  /// Armed by [tryShowTour]: when and how to mark this tour's shown-state.
  /// Cleared when the pending tour exits (finish or abort — the policy
  /// decides whether that exit writes).
  ({
    String tourId,
    HintStore store,
    String version,
    HintMarkPolicy mark,
  })? _pendingOnce;

  /// Serialized lifecycle-hook runner: one hook at a time, FIFO. A hook may
  /// call `next()`/`finish()` — the nested transition enqueues its own hooks
  /// behind the current one, so order stays `old.onStepExit → new.onStepEnter`.
  final List<Future<void> Function()> _pendingHooks = [];
  bool _hooksRunning = false;

  /// Observable tour state. Read the current value with `state.value`
  /// (`state.value.isIdle` — or the [isIdle] shorthand below).
  ValueListenable<HintState> get state => _stateNotifier;

  /// No tour is running — for UI state (disable Show buttons). Not an
  /// atomic guard for `showTour` — use [tryShowTour] for that (see below).
  ///
  /// Reads the same notifier [state] publishes, so the two can never
  /// disagree — even while a lifecycle hook is mid-transition.
  bool get isIdle => _stateNotifier.value.isIdle;

  /// Show a tour: typo validation → machine → seeding of already-mounted
  /// targets. The wait-for-target timer is armed by a machine effect.
  ///
  /// **The returned `Future` completes when the tour is *started*, not when
  /// it ends** — awaiting it means "the tour is (or will be) on screen". To
  /// observe the end, use [HintTour.onExited] or listen to [state] and watch
  /// for [HintIdle].
  ///
  /// `Future` deliberately: (1) the typo AssertionError goes into the Future
  /// (loud failure in debug from `expectLater`) instead of being thrown in
  /// the middle of someone's build; (2) later `showTour` will await fetching
  /// a server-driven tour — the signature is already ready and won't need a
  /// breaking change. For local tours you may `await` or fire-and-forget.
  ///
  /// Returns `true` when the tour went on screen, `false` when it declined
  /// to start — busy (release only: debug asserts), an empty tour, or every
  /// step stripped as a typo. In release this is the only signal;
  /// [tryShowTour] reports the same cases without the debug assert.
  ///
  /// One tour at a time — asserts in debug if busy. For an atomic
  /// fire-and-forget without asserts, use [tryShowTour].
  Future<bool> showTour(HintTour tour) async {
    assert(
      _machine.state.isIdle,
      "hintful: showTour('${tour.id}') while ${_machine.state} is active"
      ' — one tour at a time',
    );
    assert(
      tour.duplicateTargetIds.isEmpty,
      "hintful: tour '${tour.id}' has duplicate step targetIds:"
      ' ${tour.duplicateTargetIds.join(', ')}',
    );
    // Release defense: the constructor's steps>0 assert is stripped in
    // release — an empty tour must not reach the machine (`steps[0]` would
    // RangeError). No HintSkipEvent: HintSkipReason is a closed enum (no new
    // value before 2.0) and there is no step to describe.
    if (tour.steps.isEmpty) return false;

    // Release: the busy assert above is stripped — return before typo
    // classification, otherwise _withoutTypoSteps emits unknownTarget
    // diagnostics for a tour that never starts and the seed loop below
    // clobbers the running tour's registry diff.
    if (!isIdle) return false;

    final classification = classifyStepTargets(
      tour,
      {
        for (final id in _registry.ids)
          if (inScope(id)) id
      },
    );
    if (classification.typos.isNotEmpty) {
      final message = _describeTypos(tour, classification.typos);
      assert(false, message); // debug: loud failure with candidates
      tour = _withoutTypoSteps(tour, classification.typos); // release: skip
      if (tour.steps.isEmpty) return false; // nothing to show
    }

    _dispatch(HintStart(tour: tour));

    // Already-mounted targets will not fire onChange (the registry did not
    // change) — seed them synchronously, otherwise waiting(0) would spin
    // forever.
    for (final id in _registry.ids) {
      if (!inScope(id)) continue;
      _dispatch(TargetAppeared(targetId: id));
    }
    _lastKnownIds = {
      for (final id in _registry.ids)
        if (inScope(id)) id
    };
    return true;
  }

  /// Show a tour unless one is already running — atomic, no assert.
  /// Returns `false` when busy (no state change), when the versioned gate
  /// is closed, or when nothing was shown; `true` when the tour is actually
  /// on screen.
  /// Prefer over `if (isIdle) await showTour(tour)` — that check-then-act
  /// races if two callers fire at once. `isIdle` stays for UI state.
  ///
  /// [mark] decides when the store records the shown-state. The store is
  /// consulted whenever either [mark] is given **or** the tour declares
  /// [HintTour.minShowVersion] — a version floor on the tour always gates,
  /// so the field means what it says. Three cases cover everything:
  ///
  /// - no [mark] and no [HintTour.minShowVersion] — the store is not
  ///   touched at all, the tour simply shows;
  /// - no [mark] but a [HintTour.minShowVersion] — gated, and recorded with
  ///   [HintMarkPolicy.onAnyExit] (declare the floor, nothing else);
  /// - [mark] — gated, and recorded per the policy:
  ///   * [HintMarkPolicy.onFinish] — when the tour finishes (Done / last
  ///     step); skip, timeout and abort do not mark;
  ///   * [HintMarkPolicy.onAnyExit] — on any exit (finish, skip, abort);
  ///   * [HintMarkPolicy.manual] — never (the app owns the shown-state; the
  ///     gate still runs — that is the difference from omitting [mark] on a
  ///     tour with no version floor).
  ///
  /// The recorded value is [HintTour.minShowVersion] (a tour with no floor
  /// records the string `'true'` — "never show again", the same convention
  /// as the offer dialog's decline keys).
  ///
  /// The store is app-wide: configure it once with `Hintful.configure(store:
  /// ...)` — there is no per-call store (the session-in-memory fallback
  /// works, but state lives only for this run). Prefer this over hand-rolled
  /// `shouldShow` + listener glue when the "shown" definition is *finished*
  /// (see best practices §6).
  Future<bool> tryShowTour(
    HintTour tour, {
    HintMarkPolicy? mark,
  }) async {
    ({HintStore store, HintMarkPolicy mark})? armed;
    if (mark != null || tour.minShowVersion != null) {
      final effective = store;
      if (!effective.shouldShow(tour.id, minVersion: tour.minShowVersion)) {
        return false; // the versioned gate is closed
      }
      if (mark != null) {
        armed = (store: effective, mark: mark);
      } else {
        // Version floor without a policy: gate + record, nothing to decide.
        armed = (store: effective, mark: HintMarkPolicy.onAnyExit);
      }
    }
    if (!isIdle) return false;
    if (armed != null) {
      _pendingOnce = (
        tourId: tour.id,
        store: armed.store,
        version: tour.minShowVersion ?? 'true',
        mark: armed.mark,
      );
    }
    await showTour(tour);
    if (isIdle) {
      // showTour declined (every step stripped as typos, or an empty tour in
      // release) — nothing was shown, do not leave a mark armed.
      _pendingOnce = null;
      return false;
    }
    return true;
  }

  /// Fast path for a single hint: a one-step tour without HintTour ceremony.
  ///
  /// Equivalent to `tryShowTour` on a tour whose id is the step's target id
  /// prefixed with `hint:` — the same wait-for-target, timeout, typo
  /// validation and diagnostics as a full tour. The derived id is what
  /// diagnostics, store keys and the offer dialog see for this hint.
  ///
  /// Delegates to [tryShowTour], so it is atomic (returns `false` when
  /// busy) and takes [mark] for show-once. For the loud, assert-based
  /// variant use `showTour(HintTour(id: 'hint:…', steps: [step]))`.
  Future<bool> showHint(HintStep step, {HintMarkPolicy? mark}) => tryShowTour(
        HintTour(id: 'hint:${step.targetId}', steps: [step]),
        mark: mark,
      );

  @override
  void next() => _dispatch(const UserNext());

  @override
  void previous() => _dispatch(const UserPrevious());

  /// Jump to a specific step (0-based).
  ///
  /// Out-of-range and idle are both no-ops (the range assert lives in the
  /// machine — one message, one place).
  @override
  void goTo(int index) {
    if (_machine.state.tour == null) return; // no active tour
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
    _pendingHooks.clear();
    _hookedVisit = null;
    _pendingOnce = null;
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
    // While idle the machine ignores target events and the next [showTour]
    // reseeds from the registry — keep no id set between tours (zero-idle).
    if (_machine.state.isIdle) {
      _lastKnownIds = const {};
      return;
    }
    final current = {
      for (final id in _registry.ids)
        if (inScope(id)) id
    };
    final previous = _lastKnownIds;
    final appeared = current.difference(previous);
    final vanished = previous.difference(current);
    for (final id in appeared) {
      _dispatch(TargetAppeared(targetId: id));
    }
    for (final id in vanished) {
      _dispatch(TargetVanished(targetId: id));
    }
    _lastKnownIds = current;
    // Registration-only change (same id set — a target updated its
    // focusShape/focusPadding, or a list recycled an item). Nothing for the
    // machine, but the overlay must re-read the registry: its view looks
    // registrations up on every build, and `update()` is just a
    // markNeedsBuild on the live entry.
    if (appeared.isEmpty && vanished.isEmpty) {
      final state = _stateNotifier.value;
      _hostFor(state)?.update(state);
    }
  }

  void _dispatch(HintEvent event) {
    final before = _machine.state;
    final transition = _machine.dispatch(
      event,
      targetPresent: (id) => inScope(id) && _registry.lookup(id) != null,
    );
    _applyEffects(transition, before);
    _stateNotifier.value = transition.state;
    _syncStepHooks(transition.state);
    _syncTourExit(before, transition);
    // A hook may call next()/finish()/showTour() — the hook runner drains
    // synchronously up to the first `await`, so a nested `_dispatch` can run
    // to completion *inside* `_syncStepHooks` above. Rendering this
    // (possibly stale) transition then would repaint the outer step over the
    // nested one — worst case a fresh host built on top of an already
    // released (idle) one. Always render whatever is current *now*.
    final current = _stateNotifier.value;
    _hostFor(current)?.update(current);
    if (current.isIdle) {
      _timer?.cancel();
      _timer = null;
      // Zero-idle: after the tour the controller retains no tour state —
      // the registry-diff id set is dropped ([showTour] reseeds it) and the
      // overlay host (with its overlay/entry refs) is disposed. The next
      // tour lazily builds a fresh host and re-captures the overlay.
      _lastKnownIds = const {};
      _releaseHost();
    }
  }

  /// The tour-level exit hook ([HintTour.onExited]) — queued after the step
  /// hooks so the order out of a tour is `step.onStepExit → tour.onExited`.
  /// `finished` comes from this transition's own effects: a
  /// [FinishedEffect] is a normal end, everything else (skip, timeout,
  /// abort) is an early exit.
  void _syncTourExit(HintState before, HintTransition transition) {
    if (before.isIdle || !transition.state.isIdle) return;
    final hook = before.tour?.onExited;
    if (hook == null) return;
    final finished = transition.effects.any((e) => e is FinishedEffect);
    _enqueueHook(() => hook(finished));
  }

  /// Lazily builds the host at the first non-idle state: the builder is not
  /// called for headless runs and does not create an overlay without need.
  HintOverlayHost? _hostFor(HintState state) {
    if (_builtHost != null) return _builtHost;
    if (state.isIdle || _overlayHostBuilder == null) return null;
    return _builtHost = _overlayHostBuilder(this);
  }

  /// Disposes the overlay host when the tour ends: the engine holds overlay
  /// references that must not outlive the tour (zero-idle cost), and the
  /// next tour rebuilds it lazily via [_hostFor].
  void _releaseHost() {
    _builtHost?.dispose();
    _builtHost = null;
  }

  /// Brackets a *step visit* — the lifecycle contract of
  /// [HintStep.onStepEnter]/[HintStep.onStepExit]:
  ///
  /// - `onStepEnter` fires once when the step first becomes active;
  /// - `onStepExit` fires once when that visit ends: a step change,
  ///   finish, skip or abort. Target vanish (Active → Waiting for the
  ///   **same** step) keeps the visit open — neither hook re-fires when the
  ///   target returns;
  /// - consecutive visits run in order: `old.onStepExit` → `new.onStepEnter`
  ///   (FIFO via the hook runner, hooks may be async).
  void _syncStepHooks(HintState after) {
    final open = _hookedVisit;
    if (open != null) {
      final sameStepActive = after is HintActive &&
          identical(after.tour, open.tour) &&
          after.stepIndex == open.index;
      final sameStepWaiting = after is HintWaiting &&
          identical(after.tour, open.tour) &&
          after.stepIndex == open.index;
      if (!sameStepActive && !sameStepWaiting) {
        _hookedVisit = null;
        _enqueueHook(open.tour.steps[open.index].onStepExit);
      }
    }
    if (after is HintActive) {
      final already = _hookedVisit != null &&
          identical(_hookedVisit!.tour, after.tour) &&
          _hookedVisit!.index == after.stepIndex;
      if (!already) {
        _hookedVisit = (tour: after.tour, index: after.stepIndex);
        _enqueueHook(after.tour.steps[after.stepIndex].onStepEnter);
      }
    }
  }

  void _enqueueHook(Future<void> Function()? hook) {
    if (hook == null || _disposed) return;
    _pendingHooks.add(hook);
    if (!_hooksRunning) _drainHooks();
  }

  /// Runs queued hooks one at a time; a throwing hook is reported, not
  /// swallowed into the next one, and never breaks the chain.
  Future<void> _drainHooks() async {
    _hooksRunning = true;
    while (_pendingHooks.isNotEmpty && !_disposed) {
      final hook = _pendingHooks.removeAt(0);
      try {
        await hook();
      } catch (e, st) {
        // Unconditional: CHANGELOG 1.0.0 promises a throwing hook is logged —
        // release builds must not swallow failures of app-side analytics hooks.
        // Not routed to HintDiagnosticsHandler: HintSkipReason is closed and a
        // hook error is not a "step was not shown" event.
        debugPrint('hintful: step lifecycle hook threw: $e\n$st');
      }
    }
    _hooksRunning = false;
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
        case StepSkippedEffect(:final stepIndex, :final reason, :final detail):
          _reportStepSkipped(before, stepIndex, reason, detail);
          break;
        case AbortEffect(:final reason, :final detail):
          _reportStepSkipped(
            before,
            before.stepIndex ?? 0,
            reason,
            detail,
          );
          // Mark policy decides whether this exit writes: onAnyExit marks
          // even on abort/skip/timeout; onFinish and manual leave the tour
          // re-showable (the user did not finish).
          final pendingAbort = _pendingOnce;
          if (pendingAbort != null && before.tour?.id == pendingAbort.tourId) {
            if (pendingAbort.mark == HintMarkPolicy.onAnyExit) {
              pendingAbort.store
                  .markShown(pendingAbort.tourId, pendingAbort.version);
            }
            _pendingOnce = null;
          }
          break;
        case EnterStepEffect():
          break;
        case FinishedEffect(:final tourId):
          // Rendering follows the state (host.update); finish is not
          // diagnosed. tryShowTour marks per its `mark:` policy: onFinish and
          // onAnyExit both count a normal finish as "shown"; manual never
          // writes.
          final pendingFinish = _pendingOnce;
          if (pendingFinish != null && pendingFinish.tourId == tourId) {
            if (pendingFinish.mark != HintMarkPolicy.manual) {
              pendingFinish.store.markShown(tourId, pendingFinish.version);
            }
            _pendingOnce = null;
          }
          break;
      }
    }
  }

  /// A skipped step carries the "before" context: after the transition the
  /// machine already moved on, and tourId/targetId would have to be
  /// reconstructed from nothing. Covers aborts and skipStep alike.
  void _reportStepSkipped(
    HintState before,
    int stepIndex,
    HintSkipReason reason,
    String detail,
  ) {
    final tourId = before.tour?.id;
    final targetId = switch (before) {
      HintWaiting(:final targetId) => targetId,
      HintActive(:final targetId) => targetId,
      _ => null,
    };
    _diagnostics?.call(HintSkipEvent(
      tourId: tourId,
      stepIndex: stepIndex,
      targetId: targetId,
      reason: reason,
      detail: detail,
    ));
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
      _diagnostics?.call(HintSkipEvent(
        tourId: tour.id,
        stepIndex: t.index,
        targetId: t.typoId,
        reason: HintSkipReason.unknownTarget,
        detail:
            'no valid target; closest: ${t.candidates.join(', ')}; step skipped',
      ));
    }
    final removed = typos.map((t) => t.step).toSet();
    final kept = tour.steps.where((step) => !removed.contains(step)).toList();
    // hintTourWithSteps preserves every tour-level field (autoScroll, …) — a
    // manual reconstruction here once dropped autoScroll.
    return hintTourWithSteps(tour, kept);
  }
}

/// Scope filtering — deliberately an extension, not a method on
/// [HintController]: the barrel does not export it, so package consumers
/// cannot call it (the filter is engine machinery, not an app-level query;
/// drive scoping through [HintController.scopePrefix]). Kept out of the
/// class for a smaller public contract — same pattern as the registry's
/// register-path extension.
extension HintControllerScope on HintController {
  /// True when [id] belongs to this controller's scope.
  bool inScope(String id) => scopePrefix == null || id.startsWith(scopePrefix!);
}

/// A controller that renders through a custom [HintOverlayHost] builder —
/// the package's own overlay tests need it, consumers cannot: the barrel
/// exports neither this function nor the host type, so it never appears in
/// the public contract (unlike a `host:` parameter, which would force the
/// hidden type into a documented signature).
///
/// [store] overrides the app-wide `Hintful` store for this controller.
@visibleForTesting
HintController hintControllerWithHost({
  required HintOverlayHost Function(HintController) host,
  HintTargetRegistry? registry,
  HintDiagnosticsHandler? diagnostics,
  String? scopePrefix,
  HintStore? store,
}) =>
    HintController._(
      registry: registry,
      diagnostics: diagnostics,
      scopePrefix: scopePrefix,
      store: store,
      overlayHostBuilder: host,
    );
