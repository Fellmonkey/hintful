import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../widgets/default_tooltip.dart';
import '../controller.dart' show HintController, HintOverlayHost;
import '../diagnostics.dart';
import '../machine.dart';
import '../position_resolver.dart';
import '../registry.dart';
import '../specs.dart';
import '../theme/hint_theme.dart';
import 'pulse_painter.dart';
import 'scrim_painter.dart';
import 'tooltip_placement.dart';
import 'tooltip_tail.dart';

const _kTooltipGap = 12.0;
const _kWaitingText = 'Preparing…';

/// Standard render-mechanics wiring: the engine over [registry] (defaults to
/// the registry singleton — zero-config).
///
/// The only public entry into render mechanics, for `HintController`:
///
/// ```dart
/// final controller = HintController(overlayHostBuilder: defaultOverlayHost());
/// ```
///
/// The engine itself and its internals (scrim, placement delegate) stay
/// hidden: they can change without breaking, while this contract is stable.
HintOverlayHost Function(HintController) defaultOverlayHost({
  HintTargetRegistry? registry,
}) {
  return (controller) => HintOverlayEngine(
        registry: registry ?? HintTargetRegistry.defaultInstance,
        input: controller,
      );
}

/// Tour render mechanics: mounts a single `OverlayEntry`, draws the scrim
/// hole via `CompositedTransformFollower` (target position from the
/// compositor), places the tooltip, handles tap-on-overlay and keyboard.
///
/// Implements the [HintOverlayHost] contract from controller.dart: the
/// controller does not know what the overlay looks like or where the
/// `OverlayState` comes from — the engine captures it itself (the root
/// overlay of the first registered target), or receives it explicitly via
/// `overlay` for fully-deferred scenarios (zero mounted targets). User input
/// (next/skip/finish) goes into [HintActions] — the controller implements it.
class HintOverlayEngine implements HintOverlayHost {
  HintOverlayEngine({
    required HintTargetRegistry registry,
    required HintActions input,
    OverlayState? overlay,
    HintDiagnosticsHandler? diagnostics,
  })  : _registry = registry,
        _input = input,
        _overlay = overlay,
        _diagnostics = diagnostics;

  final HintTargetRegistry _registry;
  final HintActions _input;
  final HintDiagnosticsHandler? _diagnostics;
  OverlayState? _overlay;
  OverlayEntry? _entry;
  HintState? _pendingState;
  bool _disposed = false;

  @override
  void update(HintState state) {
    if (_disposed) return;
    _pendingState = state;

    if (state.isIdle) {
      _removeEntry();
      return;
    }

    final overlay = _overlay ?? _captureOverlay();
    if (overlay == null) {
      // Neither an explicit OverlayState nor a mounted target to capture
      // from: nowhere to draw — say so honestly (otherwise "why isn't it
      // visible" stays silent).
      _reportOverlayUnavailable();
      return;
    }
    _overlay = overlay;

    if (_entry == null) {
      _entry = _createEntry(overlay);
      overlay.insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _removeEntry();
    _disposed = true;
  }

  // ──────────────────────────── internals ────────────────────────────

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  /// Root overlay of the first registered target: zero-config — no need to
  /// wrap the app's screen. Returns null if there are no targets at all.
  OverlayState? _captureOverlay() {
    for (final id in _registry.ids) {
      final registration = _registry.lookup(id);
      if (registration == null) continue;
      final overlay = Overlay.maybeOf(registration.context, rootOverlay: true);
      if (overlay != null) return overlay;
    }
    return null;
  }

  void _reportOverlayUnavailable() {
    final state = _pendingState;
    final stepIndex = state?.stepIndex ?? 0;
    final targetId = switch (state) {
      HintWaiting(:final targetId) => targetId,
      HintActive(:final targetId) => targetId,
      _ => '?',
    };
    _diagnostics?.onHintSkipped(
      state?.tour?.id ?? '?',
      stepIndex,
      targetId,
      HintSkipReason.targetNotRendered,
      'overlay unavailable: no OverlayState and no mounted target to capture'
      ' from (pass overlay: explicitly for fully-deferred scenarios)',
    );
  }

  OverlayEntry _createEntry(OverlayState overlay) {
    return OverlayEntry(
      builder: (context) {
        final state = _pendingState;
        if (state == null || state.isIdle) return const SizedBox.shrink();
        return _HintOverlayView(
          state: state,
          registry: _registry,
          input: _input,
        );
      },
    );
  }
}

// ──────────────────────── entry content ────────────────────────

class _HintOverlayView extends StatefulWidget {
  const _HintOverlayView({
    required this.state,
    required this.registry,
    required this.input,
  });

  final HintState state;
  final HintTargetRegistry registry;
  final HintActions input;

  @override
  State<_HintOverlayView> createState() => _HintOverlayViewState();
}

class _HintOverlayViewState extends State<_HintOverlayView>
    with WidgetsBindingObserver {
  final FocusScopeNode _scopeNode = FocusScopeNode();

  /// The node focused before the tour stole focus, to give it back on
  /// dispose — focus must not wander off to the route when the tour ends.
  FocusNode? _restoreFocus;

  @override
  void initState() {
    super.initState();
    // `autofocus` on a FocusScope registers a node INSIDE the scope and does
    // not focus the scope itself — in an app with a Navigator, focus stays on
    // the route's scope (_ModalScopeState) and Esc/Tab/Enter never arrive
    // (worked in a bare Overlay, not in MaterialApp). An explicit
    // requestFocus post-frame after the entry mounts wins.
    //
    // The callback is registered from this State's initState, which runs
    // before the FocusScope's autofocus callback (parent initState precedes
    // child builds) — so [FocusManager.instance.primaryFocus] here is still
    // the pre-tour node, captured before the steal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreFocus = FocusManager.instance.primaryFocus;
      _scopeNode.requestFocus();
    });
    // System back (Android back button / route pop) interception for
    // `HintTour.disableBackButton`. A binding observer instead of
    // PopScope/WillPopScope: those register via `ModalRoute.of(context)`,
    // and an OverlayEntry lives ABOVE routes — it has no ModalRoute
    // ancestor, so they would be dead code. `didPopRoute` returning true
    // consumes the pop, on every Flutter version.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final restore = _restoreFocus;
    // The node may have been unmounted while the tour was active (e.g. the
    // page navigated away): `context` is null then — requestFocus on a
    // detached node is a no-op, skip it. `hasFocus` — already back where it
    // belongs (nothing to do).
    if (restore != null && restore.context != null && !restore.hasFocus) {
      restore.requestFocus();
    }
    _scopeNode.dispose();
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (widget.state.tour?.disableBackButton ?? false) {
      // Consumed: the tour owns the screen while active.
      return true;
    }
    return false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.input.skip();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.input.previous();
      } else {
        widget.input.next();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.input.next();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final stepIndex = widget.state.stepIndex;
    final tour = widget.state.tour;
    if (tour == null || stepIndex == null) return const SizedBox.shrink();
    final step = tour.steps[stepIndex];
    final hintTheme = Theme.of(context).hintTheme;

    // Waiting: the primary target does not exist yet — full scrim without a
    // hole + "preparing". No tap handling: the pointer passes through to the
    // app (the page stays scrollable while preparing), and taps are a no-op
    // anyway while waiting (the machine ignores next until the target is up).
    final body = widget.registry.lookup(step.targetId) == null
        ? _buildWaitingMode(hintTheme)
        : _buildTargetMode(
            context,
            step,
            stepIndex: stepIndex,
            totalSteps: tour.steps.length,
            theme: hintTheme,
          );

    return FocusScope(
      node: _scopeNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: body,
    );
  }

  /// Waiting: full scrim without a hole + "preparing". With a blur filter
  /// the scrim is a global `BackdropFilter`; without — the follower painter
  /// (a full-screen scrim, no hole).
  Widget _buildWaitingMode(HintTheme theme) {
    final filter = theme.imageFilter;
    final Widget scrim = filter != null
        ? ClipRect(
            child: BackdropFilter(
              filter: filter,
              child: ColoredBox(color: theme.scrimColor),
            ),
          )
        : CustomPaint(
            painter: ScrimHolePainter(
              resolvers: const [UnpositionedHintResolver()],
              color: theme.scrimColor,
              // Waiting is a deliberate full-screen dim (no hole); the
              // active mode paints nothing until positioned (see the
              // painter's doc — the no-flash rule).
              paintFullScrimWhenUnpositioned: true,
            ),
            child: const SizedBox.expand(),
          );
    return Stack(
      children: [
        Positioned.fill(child: scrim),
        Center(
          child: Text(
            _kWaitingText,
            style: TextStyle(color: theme.tooltipForeground, fontSize: 16),
          ),
        ),
      ],
    );
  }

  /// Active: the scrim holes live in the followers (moved by the compositor),
  /// the tooltip in the global layer (button hit-testing works across the
  /// whole screen, see [_ActiveOverlayContent]).
  Widget _buildTargetMode(
    BuildContext context,
    HintStep step, {
    required int stepIndex,
    required int totalSteps,
    required HintTheme theme,
  }) {
    final seen = <String>{};
    final registrations = <HintTargetRegistration>[
      for (final id in step.targetIds)
        // Dedupe by id: a repeated id within a step is harmless for the
        // machine (one hole) but would collide two followers with the same
        // GlobalKey.
        if (widget.registry.lookup(id) case final registration?)
          if (seen.add(id)) registration,
    ];
    // The machine activates a step only when ALL of its targets are mounted;
    // a target can unregister in the same frame the active state lands — be
    // defensive and fall back to waiting.
    if (registrations.isEmpty) return _buildWaitingMode(theme);
    return _ActiveOverlayContent(
      step: step,
      stepIndex: stepIndex,
      totalSteps: totalSteps,
      actions: widget.input,
      theme: theme,
      registrations: registrations,
    );
  }
}

/// Scrim holes + placed tooltip.
///
/// One follower per spotlighted target, two layer kinds:
/// - **Scrim — inside the primary's `CompositedTransformFollower`**: the
///   primary hole sits at local (0,0) with `leaderSize`; the step's other
///   holes are translated into this canvas from their own followers' live
///   transforms. The on-screen position is moved by the compositor (scroll,
///   animations, re-layout — without repaints). The screen in follower-local
///   coordinates is drawn by the painter from the resolvers' live transforms.
///   Secondary targets get resolver-only followers (nothing visible) — their
///   transforms feed the scrim painter and the tap regions.
/// - **Tooltip — in a global full-screen layout box** above the followers. In
///   follower-local coordinates the screen extends into the negative region
///   (the target is not at a screen corner), and hit-testing is bounded by
///   the box's bounds — tooltip buttons above/left of the target would be
///   unreachable (found while exercising the example app). The global box:
///   `screenLocal = Rect(0,0,W,H)`, `holeLocal = translation & leaderSize`.
///
/// Placement is recomputed **live**: the position watcher recreates the
/// `TooltipPlacementDelegate` with the current `holeLocal` on every movement
/// frame, so auto-flip and keep-in-safe-area are re-evaluated on scroll, not
/// just on step change. The known cost is a **one-frame lag** (the hole
/// moves instantly via the compositor; the tooltip catches up on the next
/// frame — inherent to snapshot placement: a compositor-driven tooltip would
/// be bounded by the follower's hit-test area and lose full-screen buttons).
/// The same lag applies to the opt-in blur scrim (its strips are built from
/// the watcher's snapshot, not read live at paint).
///
/// The single owner of the targets' positions in the overlay: it creates the
/// resolvers (compositor transforms) after the followers mount and hands them
/// to the scrim painter, the pulse and its own watcher. The watcher reads
/// the primary transform once per frame — movement → `markNeedsPaint` on the
/// scrim (the picture changes shape) + `setState` (the tooltip follows the
/// target); the first successful snapshot after mount/target-change mounts
/// the tooltip at the right place. At rest — zero repaints and zero setState.
///
/// Taps: the wrapper `GestureDetector` is **translucent** — the overlay owns
/// taps (its recognizer joins the arena first, it is the topmost hit), while
/// drags pass through to the scrollable below (the overlay registers no drag
/// recognizer), so the page scrolls under an active tour (scroll-through).
/// Tap-on-target vs tap-on-overlay is decided by the tap position against the
/// hole rects (see [_ActiveOverlayContentState._dispatchTap]).
class _ActiveOverlayContent extends StatefulWidget {
  const _ActiveOverlayContent({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.actions,
    required this.theme,
    required this.registrations,
  });

  final HintStep step;
  final int stepIndex;
  final int totalSteps;
  final HintActions actions;
  final HintTheme theme;

  /// All spotlighted targets of the step, primary first. Non-empty (the
  /// caller falls back to waiting mode when nothing is mounted).
  final List<HintTargetRegistration> registrations;

  @override
  State<_ActiveOverlayContent> createState() => _ActiveOverlayContentState();
}

class _ActiveOverlayContentState extends State<_ActiveOverlayContent>
    with SingleTickerProviderStateMixin {
  final GlobalKey _scrimPaintKey = GlobalKey();
  final GlobalKey _pulsePaintKey = GlobalKey();

  /// One follower key per target id: the follower render object is stable
  /// per id within a step and reused when the id stays across steps.
  final Map<String, GlobalKey> _followerKeys = {};

  /// Live resolvers per target id (created once the follower mounts); read
  /// by the scrim painter at paint time and by the tap regions per tap.
  final Map<String, CompositorHintResolver> _resolvers = {};

  /// The primary target's position (global coordinates). null — the tooltip
  /// is not mounted: on the mount frame the transform is not known yet, and
  /// placement at a zero position would slide off-screen. After the first
  /// successful snapshot the tooltip appears at the right place; this also
  /// handles "target off-screen" — until the target is mounted/visible,
  /// there is no tooltip.
  Offset? _translation;
  bool _pollScheduled = false;
  TapDownDetails? _lastTap;

  /// The primary hole's top-left, published to the tooltip repositioner.
  /// Movement frames update ONLY this notifier (and repaint the scrim) —
  /// the overlay subtree does not rebuild while scrolling; the repositioner
  /// (a tiny child) re-places the cached tooltip.
  final ValueNotifier<Offset?> _holeNotifier = ValueNotifier<Offset?>(null);

  /// Cached tooltip slots (the content widgets incl. the tail wrapper).
  /// Rebuilt only when the STEP changes; reused across movement frames so
  /// the tooltip content stays identical while scrolling — identical widget
  /// instances mean no re-layout of the tooltip text on every movement
  /// frame (a fresh DefaultTooltip/TextSpan per frame would re-measure
  /// paragraphs on every scroll tick). Position/layout updates still happen
  /// (the placement delegate rebuilds with the fresh hole), only the
  /// content subtree is skipped.
  List<Widget>? _slotCache;
  HintStep? _slotCacheStep;
  int? _slotCacheIndex;

  /// Pulse ring animation; created lazily — only while `theme.showPulse` is
  /// on (default off), so the common path allocates no controller/ticker.
  /// The tick repaints the pulse paint directly ([_repaintPulse]) — no
  /// rebuilds.
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    _ensurePulse();
    _syncFollowerKeys();
    _schedulePoll();
  }

  @override
  void didUpdateWidget(covariant _ActiveOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-snapshot only when the primary target changes: another leader's
    // transform is invalid. A step change on the same target keeps the
    // position — the tooltip does not flash (build re-places it for the new
    // step).
    if (oldWidget.registrations.first.link != widget.registrations.first.link) {
      _translation = null;
    }
    // Drop followers/resolvers of targets no longer in the step; add new ids.
    final currentIds = {for (final r in widget.registrations) r.id};
    _followerKeys.removeWhere((id, _) => !currentIds.contains(id));
    _resolvers.removeWhere((id, _) => !currentIds.contains(id));
    _syncFollowerKeys();
    // Step change → the cached tooltip content is stale (new title/desc/
    // buttons); the next build rebuilds the slots.
    if (!identical(_slotCacheStep, widget.step) ||
        _slotCacheIndex != widget.stepIndex) {
      _slotCache = null;
    }
    // Pulse on/off by the theme.
    _ensurePulse();
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    _holeNotifier.dispose();
    super.dispose();
  }

  void _ensurePulse() {
    if (widget.theme.showPulse) {
      _pulseController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..addListener(_repaintPulse);
      if (!_pulseController!.isAnimating) _pulseController!.repeat();
    } else {
      _pulseController?.stop();
    }
  }

  void _syncFollowerKeys() {
    for (final r in widget.registrations) {
      _followerKeys.putIfAbsent(r.id, GlobalKey.new);
    }
  }

  void _repaintPulse() {
    final renderObject = _pulsePaintKey.currentContext?.findRenderObject();
    (renderObject as RenderCustomPaint?)?.markNeedsPaint();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Translucent: the overlay owns taps (topmost → first in the arena),
      // while drags pass through to the scrollable below (scroll-through —
      // the page scrolls under an active tour). Tooltip buttons are deeper
      // than this detector, so their taps win the arena (a Material button
      // is deeper → first in the arena).
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) => _lastTap = details,
      onTap: _dispatchTap,        child: LayoutBuilder(
        builder: (context, constraints) {
          final screen = constraints.biggest;
          final primary = widget.registrations.first;
          final blur = widget.theme.imageFilter;


          // Primary follower: hosts the scrim painter (non-blur mode). In
          // blur mode the scrim is the global layer and the follower stays
          // empty (both read the live resolver). The painters must not
          // absorb pointer events: `CustomPaint` hit-tests self when it has
          // a painter, which would stop the translucent pass-through to the
          // app below (no scroll-through). IgnorePointer keeps them painting
          // while letting the hit test continue (the wrapper GestureDetector
          // still joins the arena — translucent adds itself regardless of
          // children).
          final Widget followerChild = blur == null
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: _scrimPaintKey,
                          painter: ScrimHolePainter(
                            resolvers: _resolverList(),
                            color: widget.theme.scrimColor,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink();

          return Stack(
            children: [
              CompositedTransformFollower(
                key: _followerKeys[primary.id],
                link: primary.link,
                showWhenUnlinked: false,
                child: followerChild,
              ),
              // Secondary targets: resolver-only followers (nothing visible).
              for (final r in widget.registrations.skip(1))
                CompositedTransformFollower(
                  key: _followerKeys[r.id],
                  link: r.link,
                  showWhenUnlinked: false,
                  child: const SizedBox.shrink(),
                ),
              // Opt-in blur scrim: a global layer (BackdropFilter) clipped to
              // the screen-minus-holes strips, built from the build-time hole
              // rects — one frame behind the compositor, same as the tooltip.
              if (blur != null)
                Positioned.fill(
                  child: ValueListenableBuilder<Offset?>(
                    valueListenable: _holeNotifier,
                    builder: (context, translation, _) =>
                        _buildBlurScrim(screen, translation),
                  ),
                ),
              // Pulse ring: a global layer above the scrim (the ring must be
              // visible over the blur too — inside the follower it would be
              // painted under the global BackdropFilter). Paints the ring at
              // the resolver's live translation, so it follows the target
              // while the animation tick repaints.
              if (widget.theme.showPulse) _buildPulseLayer(),
              // Full-screen layout box (getSize = biggest): tooltip buttons
              // are hit-testable anywhere on screen; taps past the tooltip
              // fall through (hitTestSelf = false) onto the scrim → next.
              // Rebuilds only on step change or a hole update (movement) —
              // the repositioner below re-places the cached tooltip content
              // without rebuilding the overlay subtree.
              _RepositionTooltip(
                hole: _holeNotifier,
                builder: (context, translation) {
                  final holeLocal =
                      translation & (primary.link.leaderSize ?? Size.zero);
                  return _buildTooltip(context, holeLocal, screen);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// The step's tooltips: the primary alone (single path) or the primary +
  /// the extra slots (multi-content) — a `CustomMultiChildLayout` placing
  /// each slot on its own side; a slot avoids the spotlighted targets and
  /// the already-placed slots, so tooltips never overlap.
  ///
  /// The slot content is [cached]; only the placement delegate is rebuilt
  /// on movement frames (see [_slotCache]).
  Widget _buildTooltip(BuildContext context, Rect holeLocal, Size screen) {
    final ctx = HintTooltipContext(
      actions: widget.actions,
      stepIndex: widget.stepIndex,
      totalSteps: widget.totalSteps,
    );
    final slots = _tooltipSlots(context, ctx);
    final extras = widget.step.moreTooltips;
    if (extras.isEmpty) {
      return CustomSingleChildLayout(
        delegate: TooltipPlacementDelegate(
          screenLocal: Offset.zero & screen,
          holeLocal: holeLocal,
          // Multi-target steps: the tooltip must not cover the other
          // spotlighted targets.
          extraHoles: _extraHoleRects(),
          position: widget.step.position,
          gap: _kTooltipGap,
          // Keep-in-safe-area: the tooltip never crosses system insets
          // (notch, home indicator).
          safeArea: MediaQuery.paddingOf(context),
        ),
        child: slots.single,
      );
    }
    return CustomMultiChildLayout(
      delegate: TooltipMultiPlacementDelegate(
        screenLocal: Offset.zero & screen,
        holeLocal: holeLocal,
        primaryPosition: widget.step.position,
        extraPositions: [for (final extra in extras) extra.position],
        extraHoles: _extraHoleRects(),
        gap: _kTooltipGap,
        safeArea: MediaQuery.paddingOf(context),
      ),
      children: [
        LayoutId(
          id: TooltipMultiPlacementDelegate.primaryId,
          child: slots.first,
        ),
        for (var i = 0; i < extras.length; i++)
          LayoutId(
            id: TooltipMultiPlacementDelegate.extraId(i),
            child: slots[i + 1],
          ),
      ],
    );
  }

  /// The cached slot contents (primary + extra slots, RAW — `LayoutId` is
  /// applied by the caller so the single-layout path adds no ParentData).
  /// Rebuilt when the step changes; the list itself is then reused on
  /// movement frames — the elements stay mounted and identical, so their
  /// build/re-layout is skipped.
  List<Widget> _tooltipSlots(BuildContext context, HintTooltipContext ctx) {
    final changed =
        _slotCache == null ||
        !identical(_slotCacheStep, widget.step) ||
        _slotCacheIndex != widget.stepIndex;
    if (!changed) return _slotCache!;
    _slotCacheStep = widget.step;
    _slotCacheIndex = widget.stepIndex;
    final extras = widget.step.moreTooltips;
    return _slotCache = [
      _tooltipSlot(context, null, ctx),
      for (var i = 0; i < extras.length; i++)
        _tooltipSlot(context, extras[i], ctx),
    ];
  }

  /// The visual content of one slot: the default tooltip — the primary with
  /// its action buttons, an extra slot informational (no buttons) with the
  /// slot's own content — or the custom builder. Wrapped in the tail when
  /// the theme asks for it (the tail points toward the hole from whichever
  /// side the slot landed on). The hole is read LIVE by the tail at paint
  /// time — the cached slot follows the moving target without a rebuild.
  Widget _tooltipSlot(
    BuildContext context,
    HintTooltip? extra,
    HintTooltipContext ctx,
  ) {
    final Widget content;
    if (extra == null) {
      if (widget.step.tooltipBuilder != null) {
        content = widget.step.tooltipBuilder!(context, widget.step, ctx);
      } else {
        content = DefaultTooltip(step: widget.step, ctx: ctx);
      }
    } else if (extra.tooltipBuilder != null) {
      content = extra.tooltipBuilder!(context, widget.step, ctx);
    } else {
      content = DefaultTooltip(
        step: widget.step,
        ctx: ctx,
        title: extra.title,
        description: extra.description,
        showActions: false,
      );
    }
    return widget.theme.showTail
        ? TooltipTail(
            holeOf: _primaryHoleGlobal,
            color: widget.theme.tooltipBackground,
            child: content,
          )
        : content;
  }

  /// The primary target's hole rect in global overlay coordinates, resolved
  /// at call time (scroll/animations move both the tooltip and the hole).
  Rect _primaryHoleGlobal() {
    final translation = _translation;
    if (translation == null) return Rect.zero;
    final primary = widget.registrations.first;
    return translation & (primary.link.leaderSize ?? Size.zero);
  }

  /// Live resolvers in registration order (primary first). The painter reads
  /// them at paint time; element-wise identity is what [ScrimHolePainter]
  /// uses to skip redundant repaints.
  List<HintPositionResolver> _resolverList() => [
        for (final r in widget.registrations)
          if (_resolvers[r.id] != null) _resolvers[r.id]!,
      ];

  /// Global rects of the secondary targets (for placement vetoes and tap
  /// regions).
  List<Rect> _extraHoleRects() => [
        for (final r in widget.registrations.skip(1))
          if (_resolvers[r.id]?.resolve()
              case PositionedHint(:final translation, :final size))
            translation & size,
      ];

  /// Global rects of ALL spotlighted targets (primary + extras) — tap
  /// regions.
  List<Rect> _currentHoleRects() {
    final translation = _translation;
    if (translation == null) return const [];
    final primary = widget.registrations.first;
    return [
      translation & (primary.link.leaderSize ?? Size.zero),
      ..._extraHoleRects(),
    ];
  }

  /// The pulse ring in the global layer: above the scrim (plain and blur),
  /// below the tooltip. The painter reads the primary resolver at paint
  /// time — the animation tick repaints every frame, so the ring follows
  /// the target without rebuilds. Wrapped in IgnorePointer like the scrim
  /// (a CustomPaint with a painter hit-tests self and would block
  /// scroll-through).
  Widget _buildPulseLayer() {
    final primary = widget.registrations.first;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: _pulsePaintKey,
          painter: PulsePainter(
            animation: _pulseController!,
            resolver: _resolvers[primary.id],
            color: widget.theme.tooltipForeground,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildBlurScrim(Size screen, Offset? translation) {
    if (translation == null) {
      // The same no-flash rule as the painter: no blur until the position is
      // known — a full-screen blur-without-hole would flash before the hole
      // appears.
      return const SizedBox.shrink();
    }
    final primary = widget.registrations.first;
    final holes = <Rect>[
      translation & (primary.link.leaderSize ?? Size.zero),
      ..._extraHoleRects(),
    ];
    final strips = ScrimHolePainter.scrimStrips(Offset.zero & screen, holes);
    return ClipPath(
      clipper: _ScrimStripsClipper(strips),
      child: BackdropFilter(
        filter: widget.theme.imageFilter!,
        child: ColoredBox(color: widget.theme.scrimColor),
      ),
    );
  }

  /// Tap dispatch by region: inside any spotlighted target — the target
  /// region, otherwise the overlay region. A per-step callback replaces the
  /// default "next" for its region; the `tapOn*` flags disable a region.
  void _dispatchTap() {
    final details = _lastTap;
    if (details == null) return;
    final step = widget.step;
    final ctx = HintTooltipContext(
      actions: widget.actions,
      stepIndex: widget.stepIndex,
      totalSteps: widget.totalSteps,
    );
    final onTarget =
        _currentHoleRects().any((h) => h.contains(details.globalPosition));
    if (onTarget) {
      if (step.onTapTarget != null) {
        step.onTapTarget!(ctx, details);
      } else if (step.tapOnTarget) {
        widget.actions.next();
      }
    } else if (step.onTapOverlay != null) {
      step.onTapOverlay!(ctx, details);
    } else if (step.tapOnOverlay) {
      widget.actions.next();
    }
  }

  /// Position watcher: reads the compositor transforms once per frame (cheap:
  /// a matrix + two-float comparison). Movement → repaint the scrim (the
  /// picture changes shape) + `setState` (the tooltip follows the target);
  /// the first successful snapshot after mount/target-change mounts the
  /// tooltip. At rest — zero repaints and zero setState.
  void _schedulePoll() {
    if (_pollScheduled) return;
    _pollScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pollScheduled = false;
      if (!mounted) return;

      _ensureResolvers();
      final primary = _resolvers[widget.registrations.first.id];
      if (primary != null) {
        final position = primary.resolve();
        if (position is PositionedHint &&
            _translation != position.translation) {
          _translation = position.translation;
          // The scrim repaints (the hole shape changed) and the tooltip
          // re-places via its listener — NO setState on the overlay subtree:
          // scrolling rebuilds nothing but these two.
          final renderObject =
              _scrimPaintKey.currentContext?.findRenderObject();
          (renderObject as RenderCustomPaint?)?.markNeedsPaint();
          _holeNotifier.value = _translation;
        }
      }
      _schedulePoll();
    });
  }

  void _ensureResolvers() {
    for (final r in widget.registrations) {
      if (_resolvers.containsKey(r.id)) continue;
      final follower = _followerKeys[r.id]?.currentContext?.findRenderObject();
      if (follower is RenderFollowerLayer) {
        _resolvers[r.id] = CompositorHintResolver(follower);
      }
    }
  }
}

/// The tooltip layer: listens to the hole notifier and rebuilds ONLY the
/// tooltip placement (the cached content child stays identical across
/// movement frames — no text re-layout). Without this boundary, every
/// scroll frame would rebuild the entire overlay subtree; with it, movement
/// touches a subtree of a few widgets.
class _RepositionTooltip extends StatefulWidget {
  const _RepositionTooltip({
    required this.hole,
    required this.builder,
  });

  /// The primary hole's top-left (global overlay coordinates).
  final ValueNotifier<Offset?> hole;

  /// Builds the tooltip layer for the current hole; null hole → nothing
  /// (the tooltip must not mount before an authoritative snapshot).
  final Widget Function(BuildContext context, Offset translation) builder;

  @override
  State<_RepositionTooltip> createState() => _RepositionTooltipState();
}

class _RepositionTooltipState extends State<_RepositionTooltip> {
  @override
  void initState() {
    super.initState();
    widget.hole.addListener(_onHoleChanged);
  }

  @override
  void didUpdateWidget(covariant _RepositionTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hole != widget.hole) {
      oldWidget.hole.removeListener(_onHoleChanged);
      widget.hole.addListener(_onHoleChanged);
    }
  }

  @override
  void dispose() {
    widget.hole.removeListener(_onHoleChanged);
    super.dispose();
  }

  void _onHoleChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final translation = widget.hole.value;
    if (translation == null) return const SizedBox.shrink();
    return widget.builder(context, translation);
  }
}

/// Clip to the scrim strips (screen minus the step's holes): the blur
/// `BackdropFilter` samples the full backdrop but is only visible outside
/// the holes.
class _ScrimStripsClipper extends CustomClipper<Path> {
  const _ScrimStripsClipper(this.strips);

  final List<Rect> strips;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final strip in strips) {
      path.addRect(strip);
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _ScrimStripsClipper oldClipper) =>
      !listEquals(oldClipper.strips, strips);
}
