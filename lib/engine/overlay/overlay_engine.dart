import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../widgets/default_tooltip.dart';
import '../controller.dart' show HintController, HintOverlayHost;
import '../diagnostics.dart';
import '../machine.dart';
import '../motion.dart' show hintTransitionDuration;
import '../position_resolver.dart';
import '../registry.dart';
import '../specs.dart';
import '../theme/hint_theme.dart';
import 'pulse_painter.dart';
import 'scrim_painter.dart';
import 'tooltip_placement.dart';
import 'tooltip_tail.dart';

/// Standard render-mechanics wiring: the engine over [registry] (defaults to
/// the registry singleton — zero-config).
///
/// The only public entry into render mechanics, for `HintController`:
///
/// ```dart
/// final controller = HintController(overlayHostBuilder: defaultOverlayHost());
/// ```
///
/// Pass [overlay] explicitly for targetRect-only tours with zero mounted
/// targets (nothing to capture the root overlay from — see `targetRect`).
/// It is a provider, not a value: it is called when the host is built
/// lazily on the first non-idle state, so a `GlobalKey<OverlayState>` from
/// the widget tree is already usable there:
///
/// ```dart
/// final overlayKey = GlobalKey<OverlayState>();
/// HintController(
///   overlayHostBuilder: defaultOverlayHost(
///     overlay: () => overlayKey.currentState,
///   ),
/// );
/// ```
///
/// The engine itself and its internals (scrim, placement delegate) stay
/// hidden: they can change without breaking, while this contract is stable.
HintOverlayHost Function(HintController) defaultOverlayHost({
  HintTargetRegistry? registry,
  OverlayState? Function()? overlay,
}) {
  return (controller) => HintOverlayEngine(
        registry: registry ?? HintTargetRegistry.defaultInstance,
        input: controller,
        overlay: overlay?.call(),
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

    // Rect-anchored step: explicit coordinates win over the registry (a
    // step whose point is `targetRect` spotlights exactly that rect — even
    // when its `targetId` happens to be registered too).
    //
    // Waiting: the primary target does not exist yet — full scrim without a
    // hole + "preparing". No tap handling: the pointer passes through to the
    // app (the page stays scrollable while preparing), and taps are a no-op
    // anyway while waiting (the machine ignores next until the target is up).
    final body = step.hasRectTarget
        ? _RectTargetContent(
            step: step,
            stepIndex: stepIndex,
            totalSteps: tour.steps.length,
            actions: widget.input,
            theme: hintTheme,
          )
        : widget.registry.lookup(step.targetId) == null
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
            theme.tooltipLabels.preparing,
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
      tourAutoScroll: widget.state.tour?.autoScroll ?? false,
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
/// The same lag applies to the opt-in blur scrim (its clip is built from
/// the watcher's snapshot, not read live at paint).
///
/// The single owner of the targets' positions in the overlay: it creates the
/// resolvers (compositor transforms) after the followers mount and hands them
/// to the scrim painter, the pulse and its own watcher. The watcher reads
/// the primary transform once per frame — movement → `markNeedsPaint` on the
/// scrim (the picture changes shape) + hole-notifier (the tooltip follows
/// without rebuilding the overlay subtree); the first successful snapshot
/// after mount/target-change mounts the tooltip at the right place. At
/// rest — zero repaints and zero setState.
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
    this.tourAutoScroll = false,
  });

  final HintStep step;
  final int stepIndex;
  final int totalSteps;
  final HintActions actions;
  final HintTheme theme;
  final bool tourAutoScroll;

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
  final Map<String, HintPositionResolver> _resolvers = {};

  /// The primary target's position (global coordinates). null — the tooltip
  /// is not mounted: on the mount frame the transform is not known yet, and
  /// placement at a zero position would slide off-screen. After the first
  /// successful snapshot the tooltip appears at the right place; this also
  /// handles "target off-screen" — until the target is mounted/visible,
  /// there is no tooltip.
  Offset? _translation;
  bool _pollScheduled = false;
  TapDownDetails? _lastTap;

  /// Scroll-driven translation: the nearest ancestor Scrollable that
  /// contains the primary target is observed. On scroll the target's
  /// global position moves by -delta, so the hole/tooltip are shifted
  /// synchronously — no one-frame lag. Re-measured on (re-)attach.
  ScrollPosition? _scrollPos;
  double _scrollLastPixels = 0;
  Axis _scrollAxis = Axis.vertical;

  /// Cached tooltip slots (the content widgets incl. the tail wrapper),
  /// with the step they were built for. Rebuilt only when the STEP changes;
  /// reused across movement frames so the tooltip content stays identical
  /// while scrolling — identical widget instances mean no re-layout of the
  /// tooltip text on every movement frame (a fresh DefaultTooltip/TextSpan
  /// per frame would re-measure paragraphs on every scroll tick).
  /// Position/layout updates still happen (the placement delegate rebuilds
  /// with the fresh hole), only the content subtree is skipped.
  ({HintStep step, int index, List<Widget> slots})? _slotCache;

  FocusShape _effectiveShape() {
    final s = widget.step.focusShape;
    if (s != null) return s;
    final t = widget.registrations.first.focusShape;
    if (t != null) return t;
    return FocusShape.rectangle;
  }

  double _effectivePadding() {
    final s = widget.step.focusPadding;
    if (s != null) return s;
    final t = widget.registrations.first.focusPadding;
    if (t != null) return t;
    return 4.0;
  }

  bool _effectiveAutoScroll() =>
      widget.step.autoScroll ?? widget.tourAutoScroll;

  void _maybeAutoScroll() {
    if (!_effectiveAutoScroll()) return;
    final ctx = widget.registrations.first.context;
    if (Scrollable.maybeOf(ctx) == null) return;
    try {
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final screen = Offset.zero & MediaQuery.sizeOf(ctx);
      if (screen.contains(rect.topLeft) && screen.contains(rect.bottomRight)) return;
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } catch (_) {}
  }

  /// The primary hole's top-left, published to the tooltip placement
  /// listener. Movement frames update ONLY this notifier (and repaint the
  /// scrim) — the overlay subtree does not rebuild while scrolling; the
  /// listener (a tiny child) re-places the cached tooltip.
  final ValueNotifier<Offset?> _holeNotifier = ValueNotifier<Offset?>(null);

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
    _seedStaticPositions();
    _schedulePoll();
    // Defer: the primary target's Scrollable ancestor is not attached
    // during initState (the overlay Entry builds before the target's
    // Scrollable mounts in the same frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _attachScrollListeners();
        _maybeAutoScroll();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ActiveOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The primary target changed (steps never share one — the controller
    // asserts duplicate targetIds): the old transform is invalid, so drop
    // the snapshot...
    if (oldWidget.registrations.first.link != widget.registrations.first.link) {
      _translation = null;
      // Unmount the tooltip for the transition frame: the notifier still
      // holds the old hole, and painting the old step's tooltip at the old
      // position for a frame is the same misalignment the scrim's no-flash
      // rule forbids. The snapshot below remounts it at the right place.
      _holeNotifier.value = null;
    }
    // Drop followers/resolvers of targets no longer in the step; add new ids.
    final currentIds = {for (final r in widget.registrations) r.id};
    _followerKeys.removeWhere((id, _) => !currentIds.contains(id));
    _resolvers.removeWhere((id, _) => !currentIds.contains(id));
    _syncFollowerKeys();
    // Re-seed synchronously so the next build already has positioned
    // content — no blank flash, no stale tooltip. Live resolvers upgrade
    // behind in the poll.
    _seedStaticPositions();
    // Scroll listeners are bound to the primary target — re-bind on target
    // change (otherwise the old Scrollable would be observed).
    if (oldWidget.registrations.first.link !=
        widget.registrations.first.link) {
      _detachScrollListeners();
      _attachScrollListeners();
      // Auto-scroll the new primary into view if the step opts in.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAutoScroll();
      });
    }
    // Note: the tooltip slot cache is NOT invalidated here — _tooltipSlots
    // detects the step change itself on the next build (the single check
    // lives in exactly one place).
    // Pulse on/off by the theme.
    _ensurePulse();
  }

  @override
  void dispose() {
    _detachScrollListeners();
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
    return _TapShell(
      onTapDown: (details) => _lastTap = details,
      onTap: _dispatchTap,
      builder: (context, screen) {
        final primary = widget.registrations.first;
        final blur = widget.theme.imageFilter;

        // Followers: only for link tracking (the scrim is now global,
        // full-screen, so it never leaves a bottom gap when the target
        // moves — the hole is punched at the live global rects).
        final Widget followerChild = const SizedBox.shrink();

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
              // Global scrim: always full-screen, hole(s) at the live global
              // rects — no follower offset, no bottom flicker on scroll.
              // Plain: isolated dim + clear holes; Blur: even-odd clip.
              // Rebuilt synchronously on scroll via _holeNotifier, so the
              // dim and the tooltip move in the same frame as the content.
              Positioned.fill(
                child: ValueListenableBuilder<Offset?>(
                  valueListenable: _holeNotifier,
                  builder: (context, _, __) {
                    final holes = _visualHoleRects();
                    if (blur == null) {
                      return IgnorePointer(
                        child: CustomPaint(
                          key: _scrimPaintKey,
                          painter: RectScrimPainter(
                            holes: holes,
                            color: widget.theme.scrimColor,
                            focusShape: _effectiveShape(),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      );
                    }
                    return _buildBlurScrim(screen, holes);
                  },
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
              // Listens to the hole notifier and rebuilds ONLY the tooltip
              // placement (the cached content child stays identical across
              // movement frames — no text re-layout).
              ValueListenableBuilder<Offset?>(
                valueListenable: _holeNotifier,
                builder: (context, translation, _) {
                  // No authoritative snapshot yet: the tooltip must not
                  // mount at a zero position (it would slide off-screen).
                  if (translation == null) return const SizedBox.shrink();
                  final holeLocal =
                      translation & (primary.link.leaderSize ?? Size.zero);
                  return _buildTooltip(context, holeLocal, screen);
                },
              ),
            ],
          );
        },
      );
  }

  /// The step's tooltips: the primary alone (single path) or the primary +
  /// the extra slots (multi-content) — a `CustomMultiChildLayout` placing
  /// each slot on its own side; a slot avoids the spotlighted targets and
  /// the already-placed slots, so tooltips never overlap.
  Widget _buildTooltip(BuildContext context, Rect holeLocal, Size screen) {
    final ctx = HintTooltipContext(
      actions: widget.actions,
      stepIndex: widget.stepIndex,
      totalSteps: widget.totalSteps,
    );
    final slots = _tooltipSlots(context, ctx);
    final extras = widget.step.moreTooltips;
    if (extras.isEmpty) {
      // The cached slot stays identical across movement frames (no text
      // re-layout while scrolling); only the placement delegate rebuilds.
      return _placedPrimaryTooltip(
        context: context,
        step: widget.step,
        stepIndex: widget.stepIndex,
        content: slots.single,
        hole: holeLocal,
        screen: screen,
        extraHoles: _extraHoleRects(),
      );
    }
    final content = CustomMultiChildLayout(
      delegate: TooltipMultiPlacementDelegate(
        screenLocal: Offset.zero & screen,
        holeLocal: holeLocal,
        primaryPosition: widget.step.position,
        extraPositions: [for (final extra in extras) extra.position],
        extraHoles: _extraHoleRects(),
                safeArea: MediaQuery.paddingOf(context),
      ),
      children: [
        LayoutId(id: TooltipMultiPlacementDelegate.primaryId, child: slots.first),
        for (var i = 0; i < extras.length; i++) LayoutId(id: TooltipMultiPlacementDelegate.extraId(i), child: slots[i + 1]),
      ],
    );
    return _tooltipEntry(
      context: context,
      step: widget.step,
      stepIndex: widget.stepIndex,
      child: content,
    );
  }

  /// The cached slot contents (primary + extra slots, RAW — `LayoutId` is
  /// applied by the caller so the single-layout path adds no ParentData).
  /// Rebuilt when the step changes; the list itself is then reused on
  /// movement frames — the elements stay mounted and identical, so their
  /// build/re-layout is skipped.
  List<Widget> _tooltipSlots(BuildContext context, HintTooltipContext ctx) {
    var cache = _slotCache;
    if (cache == null ||
        !identical(cache.step, widget.step) ||
        cache.index != widget.stepIndex) {
      final extras = widget.step.moreTooltips;
      cache = _slotCache = (
        step: widget.step,
        index: widget.stepIndex,
        slots: [
          _tooltipSlot(context, null, ctx),
          for (var i = 0; i < extras.length; i++)
            _tooltipSlot(context, extras[i], ctx),
        ],
      );
    }
    return cache.slots;
  }

  /// The visual content of one slot: the primary (shared content + a tail
  /// that reads the hole LIVE at paint time, so the cached slot follows a
  /// moving target without a rebuild) or an extra slot — informational (no
  /// buttons) with its own content — or a custom builder.
  Widget _tooltipSlot(
    BuildContext context,
    HintTooltip? extra,
    HintTooltipContext ctx,
  ) {
    if (extra == null) {
      return _primaryTooltipSlot(
        context: context,
        step: widget.step,
        ctx: ctx,
        theme: widget.theme,
        holeOf: _primaryHoleGlobal,
      );
    }
    final Widget content;
    if (extra.tooltipBuilder != null) {
      content = extra.tooltipBuilder!(context, widget.step, ctx);
    } else {
      content = DefaultTooltip(
        step: widget.step,
        ctx: ctx,
        title: extra.effectiveTitle(context),
        description: extra.effectiveDescription(context),
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
    if (_translation == null) return const [];
    return [_primaryHoleGlobal(), ..._extraHoleRects()];
  }

  /// Visual holes: tap rects inflated by the effective focus padding
  /// (positive expands, negative shrinks — may become empty and is then
  /// skipped by the painter/clip).
  List<Rect> _visualHoleRects() {
    final pad = _effectivePadding();
    if (pad == 0) return _currentHoleRects();
    return [for (final r in _currentHoleRects()) r.inflate(pad)];
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
            focusShape: _effectiveShape(),
            focusPadding: _effectivePadding(),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// Opt-in blur scrim: a global layer (BackdropFilter) clipped to
  /// the screen minus the step's holes. Holes are the live global rects.
  Widget _buildBlurScrim(Size screen, List<Rect> holes) {
    return _blurScrim(
      screen: screen,
      holes: holes,
      focusShape: _effectiveShape(),
      theme: widget.theme,
    );
  }

  /// Tap dispatch by region: inside any spotlighted target — the target
  /// region, otherwise the overlay region. A per-step callback replaces the
  /// default "next" for its region; the `tapOn*` flags disable a region.
  void _dispatchTap() {
    final details = _lastTap;
    if (details == null) return;
    _dispatchStepTap(
      step: widget.step,
      actions: widget.actions,
      stepIndex: widget.stepIndex,
      totalSteps: widget.totalSteps,
      holes: _currentHoleRects(),
      details: details,
    );
  }

  /// Position watcher: reads the compositor transforms once per frame (cheap:
  /// a matrix + two-float comparison). Movement → repaint the scrim (the
  /// picture changes shape) + hole-notifier (the tooltip follows the target
  /// without rebuilding the overlay subtree). The first successful snapshot
  /// after mount/target-change mounts the tooltip AND rebuilds once so the
  /// scrim receives the live holes. At rest — zero repaints and zero
  /// setState.
  void _schedulePoll() {
    if (_pollScheduled) return;
    _pollScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pollScheduled = false;
      if (!mounted) return;

      _ensureResolvers();
      // Lazily bind scroll listener once the follower (and thus the
      // target's Scrollable) is mounted — initState is too early.
      if (_scrollPos == null) _attachScrollListeners();
      final primary = _resolvers[widget.registrations.first.id];
      if (primary != null) {
        final position = primary.resolve();
        if (position is PositionedHint &&
            _translation != position.translation) {
          if (_translation == null) {
            // First snapshot after mount/target-change: the scrim painter
            // was built with an empty resolver snapshot, so rebuild once
            // with the populated list. The tooltip mounts via its listener
            // below either way.
            setState(() {});
          }
          _translation = position.translation;
          // Always repaint explicitly: a rebuild with identical resolvers
          // skips it via `shouldRepaint` (e.g. the follower re-linking
          // after the target was culled from painting).
          final renderObject =
              _scrimPaintKey.currentContext?.findRenderObject();
          (renderObject as RenderCustomPaint?)?.markNeedsPaint();
          _holeNotifier.value = _translation;
        } else if (position is! PositionedHint && _translation != null) {
          // The follower unlinked (its leader stopped painting — scrolled
          // out / culled) while a position was known: retract the spotlight
          // instead of freezing it on the background. The scrim itself goes
          // quiet through the unlinked follower (`showWhenUnlinked: false`);
          // the tooltip unmounts via its listener. The next snapshot
          // re-mounts everything through the first-snapshot path above.
          _translation = null;
          _holeNotifier.value = null;
        }
      }
      _schedulePoll();
    });
  }

  void _ensureResolvers() {
    var upgraded = false;
    for (final r in widget.registrations) {
      if (_resolvers[r.id] is CompositorHintResolver) continue;
      final follower = _followerKeys[r.id]?.currentContext?.findRenderObject();
      if (follower is RenderFollowerLayer) {
        // Static snapshot → live compositor tracking (same values ± subpixel).
        _resolvers[r.id] = CompositorHintResolver(follower);
        upgraded = true;
      }
    }
    if (upgraded && mounted) setState(() {});
  }

  /// Synchronous position snapshot straight from the targets' own render
  /// objects — no followers, no compositor, no waiting a frame. Called in
  /// initState and on primary change so the very first build already paints
  /// positioned content — dim with a hole and a placed tooltip — instead of
  /// flashing normal UI for a frame.
  void _seedStaticPositions() {
    for (final r in widget.registrations) {
      if (_resolvers.containsKey(r.id)) continue;
      final position = _measureSync(r);
      if (position != null) _resolvers[r.id] = _StaticPosition(position);
    }
    final primary = _resolvers[widget.registrations.first.id]?.resolve();
    if (primary is PositionedHint) {
      _translation = primary.translation;
      _holeNotifier.value = primary.translation;
    }
  }

  /// Measures [registration] synchronously via its own render object.
  /// Valid exactly when the target is laid out (the common start case);
  /// null when there is nothing reliable to read yet, and the live path
  /// takes over.
  PositionedHint? _measureSync(HintTargetRegistration registration) {
    try {
      final box = registration.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return null;
      return PositionedHint(
        translation: box.localToGlobal(Offset.zero),
        size: box.size,
      );
    } catch (_) {
      return null;
    }
  }

  void _attachScrollListeners() {
    _detachScrollListeners();
    ScrollableState? found;
    widget.registrations.first.context.visitAncestorElements((e) {
      if (found != null) return false;
      if (e.widget is Scrollable) {
        found = (e as StatefulElement).state as ScrollableState;
        return false;
      }
      return true;
    });
    if (found == null) return;
    _scrollPos = found!.position;
    _scrollAxis = found!.widget.axis;
    _scrollLastPixels = _scrollPos!.pixels;
    _scrollPos!.addListener(_onScroll);
  }

  void _detachScrollListeners() {
    _scrollPos?.removeListener(_onScroll);
    _scrollPos = null;
  }

  void _onScroll() {
    if (!mounted || _translation == null || _scrollPos == null) return;
    final cur = _scrollPos!.pixels;
    if (cur == _scrollLastPixels) return;
    final d = cur - _scrollLastPixels;
    _scrollLastPixels = cur;
    final delta = _scrollAxis == Axis.vertical ? Offset(0, -d) : Offset(-d, 0);
    _translation = _translation! + delta;
    _holeNotifier.value = _translation;
    final ro = _scrimPaintKey.currentContext?.findRenderObject();
    (ro as RenderCustomPaint?)?.markNeedsPaint();
    _repaintPulse();
  }
}

/// A frozen position snapshot (see `_seedStaticPositions`): resolves to a
/// fixed [PositionedHint]. Lives in the resolvers map only until its
/// follower mounts and upgrades it to a [CompositorHintResolver].
class _StaticPosition implements HintPositionResolver {
  _StaticPosition(this._position);

  final PositionedHint _position;

  @override
  HintPosition resolve() => _position;
}

/// Shared overlay shell: translucent tap handling over a full-screen
/// layout box. Both contents (follower-anchored and rect-anchored) share
/// this tap contract — taps dispatched by region, drags passing through to
/// the page below (scroll-through) — so it cannot drift between the two.
class _TapShell extends StatelessWidget {
  const _TapShell({
    required this.onTapDown,
    required this.onTap,
    required this.builder,
  });

  final ValueChanged<TapDownDetails> onTapDown;
  final VoidCallback onTap;

  /// Builds the overlay content for the full [screen] size.
  final Widget Function(BuildContext context, Size screen) builder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Translucent: the overlay owns taps (topmost → first in the arena),
      // while drags pass through to the scrollable below (scroll-through —
      // the page scrolls under an active tour). Tooltip buttons are deeper
      // than this detector, so their taps win the arena (a Material button
      // is deeper → first in the arena).
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) => onTapDown(details),
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) => builder(context, constraints.biggest),
      ),
    );
  }
}

/// One blur scrim for any hole list: a global `BackdropFilter` clipped to
/// the screen minus the holes (even-odd clip — no boolean geometry).
/// Shared by the follower-anchored and rect-anchored content.
Widget _blurScrim({
  required Size screen,
  required List<Rect> holes,
  required FocusShape focusShape,
  required HintTheme theme,
}) {
  return ClipPath(
    clipper: _EvenOddClipper(
      ScrimHolePainter.scrimClipPath(
        Offset.zero & screen,
        holes,
        focusShape,
      ),
    ),
    child: BackdropFilter(
      filter: theme.imageFilter!,
      child: ColoredBox(color: theme.scrimColor),
    ),
  );
}

/// Tap dispatch by hole region, shared by the follower-anchored content and
/// the rect-anchored content: inside any hole — the target region, otherwise
/// the overlay region. A per-step callback replaces the default "next" for
/// its region; the `tapOn*` flags disable a region.
void _dispatchStepTap({
  required HintStep step,
  required HintActions actions,
  required int stepIndex,
  required int totalSteps,
  required List<Rect> holes,
  required TapDownDetails details,
}) {
  final ctx = HintTooltipContext(
    actions: actions,
    stepIndex: stepIndex,
    totalSteps: totalSteps,
  );
  final onTarget = holes.any((h) => h.contains(details.globalPosition));
  if (onTarget) {
    if (step.onTapTarget != null) {
      step.onTapTarget!(ctx, details);
    } else if (step.tapOnTarget) {
      actions.next();
    }
  } else if (step.onTapOverlay != null) {
    step.onTapOverlay!(ctx, details);
  } else if (step.tapOnOverlay) {
    actions.next();
  }
}

/// Primary tooltip content: default or custom, with tail. Shared by the
/// follower-anchored slots and the rect-anchored content — one source for
/// what a primary slot looks like.
Widget _primaryTooltipSlot({
  required BuildContext context,
  required HintStep step,
  required HintTooltipContext ctx,
  required HintTheme theme,
  required Rect Function() holeOf,
}) {
  final Widget content;
  if (step.tooltipBuilder != null) {
    content = step.tooltipBuilder!(context, step, ctx);
  } else {
    content = DefaultTooltip(step: step, ctx: ctx);
  }
  return theme.showTail
      ? TooltipTail(
          holeOf: holeOf,
          color: theme.tooltipBackground,
          child: content,
        )
      : content;
}

/// One primary tooltip: placed around [hole] with an entry transition.
/// The [content] widget is supplied by the caller — the follower path passes
/// its cached slot (identical instances across movement frames skip text
/// re-layout while scrolling).
Widget _placedPrimaryTooltip({
  required BuildContext context,
  required HintStep step,
  required int stepIndex,
  required Widget content,
  required Rect hole,
  required Size screen,
  required List<Rect> extraHoles,
}) {
  final placed = CustomSingleChildLayout(
    delegate: TooltipPlacementDelegate(
      screenLocal: Offset.zero & screen,
      holeLocal: hole,
      extraHoles: extraHoles,
      position: step.position,
      safeArea: MediaQuery.paddingOf(context),
    ),
    child: content,
  );
  return _tooltipEntry(
    context: context,
    step: step,
    stepIndex: stepIndex,
    child: placed,
  );
}

/// Entry transition (`D5`/`22`) for a step's tooltip — rung 2 of the
/// animation ladder, one arm per [HintCurve] preset:
///
/// - [HintCurve.easeOut] — the quiet preset: a plain fade with a whisper of
///   scale (0.96 → 1) on `Curves.easeOut`;
/// - [HintCurve.sprung] — the bounce: scale 0.8 → 1 on `Curves.elasticOut`
///   (the overshoot is the bounce).
///
/// Each preset has its own default length ([_presetDuration]), overridable per
/// step with [HintStep.transitionDuration], and all of them are skipped
/// (instant) under the system reduce-motion setting. Adding a preset is one
/// [HintCurve] value, one arm here and its default in [_presetDuration];
/// anything richer stays rung 3 (`tooltipBuilder`).
Widget _tooltipEntry({
  required BuildContext context,
  required HintStep step,
  required int stepIndex,
  required Widget child,
}) {
  final preset = step.transitionCurve;
  if (preset == null) return child; // rung 1: the tooltip simply appears
  final duration = hintTransitionDuration(
    MediaQuery.of(context),
    step.transitionDuration ?? _presetDuration(preset),
  );
  if (duration == Duration.zero) return child; // reduce motion

  final key = ValueKey('$stepIndex-${step.hashCode}');
  return switch (preset) {
    HintCurve.easeOut => TweenAnimationBuilder<double>(
        key: key,
        tween: Tween(begin: 0.0, end: 1.0),
        duration: duration,
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.96 + 0.04 * t,
            alignment: Alignment.center,
            child: child,
          ),
        ),
        child: child,
      ),
    HintCurve.sprung => TweenAnimationBuilder<double>(
        key: key,
        tween: Tween(begin: 0.8, end: 1.0),
        duration: duration,
        curve: Curves.elasticOut,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
        ),
        child: child,
      ),
  };
}

/// Default length of each preset — the preset's own timing, overridable per
/// step with [HintStep.transitionDuration].
Duration _presetDuration(HintCurve preset) => switch (preset) {
      HintCurve.easeOut => const Duration(milliseconds: 200),
      HintCurve.sprung => const Duration(milliseconds: 800),
    };

/// Rect-anchored step content ([HintStep.targetRect]): a static spotlight at
/// explicit overlay coordinates — no registry targets, no followers, no
/// position watching.
///
/// The scrim is a full-screen global layer ([RectScrimPainter]) and the
/// tooltip is placed once against the static hole (nothing moves, so there
/// is no reposition listener and no slot cache). Primary tooltip only: extra
/// slots ([HintStep.moreTooltips]) and the pulse ring need live targets and
/// are not rendered in this mode.
class _RectTargetContent extends StatefulWidget {
  const _RectTargetContent({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.actions,
    required this.theme,
  });

  final HintStep step;
  final int stepIndex;
  final int totalSteps;
  final HintActions actions;
  final HintTheme theme;

  @override
  State<_RectTargetContent> createState() => _RectTargetContentState();
}

class _RectTargetContentState extends State<_RectTargetContent> {
  TapDownDetails? _lastTap;

  FocusShape _effectiveShape() =>
      widget.step.focusShape ?? FocusShape.rectangle;

  Rect get _hole =>
      widget.step.targetRect!.inflate(widget.step.focusPadding ?? 4.0);

  @override
  Widget build(BuildContext context) {
    return _TapShell(
      onTapDown: (details) => _lastTap = details,
      onTap: _dispatchTap,
      builder: (context, screen) {
        final hole = _hole;
        final Widget scrim = widget.theme.imageFilter != null
            ? _blurScrim(
                screen: screen,
                holes: [hole],
                focusShape: _effectiveShape(),
                theme: widget.theme,
              )
            : CustomPaint(
                painter: RectScrimPainter(
                  holes: [hole],
                  color: widget.theme.scrimColor,
                  focusShape: _effectiveShape(),
                ),
                child: const SizedBox.expand(),
              );
        return Stack(
          children: [
            Positioned.fill(child: IgnorePointer(child: scrim)),
            _rectTooltip(context, hole, screen),
          ],
        );
      },
    );
  }

  void _dispatchTap() {
    final details = _lastTap;
    if (details == null) return;
    _dispatchStepTap(
      step: widget.step,
      actions: widget.actions,
      stepIndex: widget.stepIndex,
      totalSteps: widget.totalSteps,
      holes: [_hole],
      details: details,
    );
  }

  /// The primary tooltip slot at the static hole: shared content, placed
  /// once (nothing moves, so no slot cache and no hole listener).
  Widget _rectTooltip(BuildContext context, Rect hole, Size screen) {
    final ctx = HintTooltipContext(
      actions: widget.actions,
      stepIndex: widget.stepIndex,
      totalSteps: widget.totalSteps,
    );
    return _placedPrimaryTooltip(
      context: context,
      step: widget.step,
      stepIndex: widget.stepIndex,
      content: _primaryTooltipSlot(
        context: context,
        step: widget.step,
        ctx: ctx,
        theme: widget.theme,
        holeOf: () => hole,
      ),
      hole: hole,
      screen: screen,
      extraHoles: const [],
    );
  }
}

/// Clip to a prebuilt even-odd path (screen minus holes, see
/// `ScrimHolePainter.scrimClipPath`): the blur `BackdropFilter` samples the
/// full backdrop but stays visible only outside the holes. One clipper for
/// every blur scrim — only the path differs.
class _EvenOddClipper extends CustomClipper<Path> {
  const _EvenOddClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _EvenOddClipper old) => old.path != path;
}





