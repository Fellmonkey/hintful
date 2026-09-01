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
    final registration = widget.registry.lookup(step.targetId);
    final hintTheme = Theme.of(context).hintTheme;

    final body = registration == null
        ? _buildWaitingMode(hintTheme)
        : _buildTargetMode(
            context,
            registration,
            step,
            stepIndex: stepIndex,
            totalSteps: tour.steps.length,
            theme: hintTheme,
          );

    // For now a single tap anywhere on the overlay = next (distinguishing
    // "on target" vs "on scrim" taps with tap positions is follow-up work).
    // Tooltip buttons sit higher in the hit-test tree than this
    // GestureDetector, so their taps win the arena (a Material button is
    // deeper → first in the arena).
    return FocusScope(
      node: _scopeNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.input.next,
        child: body,
      ),
    );
  }

  /// Waiting: the target does not exist yet — full scrim without a hole +
  /// "preparing".
  Widget _buildWaitingMode(HintTheme theme) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: ScrimHolePainter(
              resolver: const UnpositionedHintResolver(),
              color: theme.scrimColor,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Center(
          child: Text(
            _kWaitingText,
            style: TextStyle(color: theme.tooltipForeground, fontSize: 16),
          ),
        ),
      ],
    );
  }

  /// Active: the scrim hole lives in the follower (moved by the compositor),
  /// the tooltip in the global layer (button hit-testing works across the
  /// whole screen, see [_ActiveOverlayContent]).
  Widget _buildTargetMode(
    BuildContext context,
    HintTargetRegistration registration,
    HintStep step, {
    required int stepIndex,
    required int totalSteps,
    required HintTheme theme,
  }) {
    return _ActiveOverlayContent(
      link: registration.link,
      step: step,
      stepIndex: stepIndex,
      totalSteps: totalSteps,
      actions: widget.input,
      theme: theme,
    );
  }
}

/// Scrim + placed tooltip.
///
/// Two layers with different coordinate natures:
/// - **Scrim hole — inside a `CompositedTransformFollower`**: the hole sits
///   at local (0,0) with `leaderSize`; its on-screen position is moved by the
///   compositor (scroll, animations, re-layout — without repaints). The
///   screen in follower-local coordinates is drawn by the painter from the
///   resolver's live transform.
/// - **Tooltip — in a global full-screen layout box** above the follower. In
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
///
/// The single owner of the target's position in the overlay: it creates the
/// resolver (compositor transform) after the follower mounts and hands it to
/// both the scrim painter and its own watcher. The watcher reads the
/// transform once per frame — movement → `markNeedsPaint` on the scrim (the
/// picture changes shape) + `setState` (the tooltip follows the target); the
/// first successful snapshot after mount/target-change mounts the tooltip at
/// the right place. At rest — zero repaints and zero setState.
class _ActiveOverlayContent extends StatefulWidget {
  const _ActiveOverlayContent({
    required this.link,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.actions,
    required this.theme,
  });

  final LayerLink link;
  final HintStep step;
  final int stepIndex;
  final int totalSteps;
  final HintActions actions;
  final HintTheme theme;

  @override
  State<_ActiveOverlayContent> createState() => _ActiveOverlayContentState();
}

class _ActiveOverlayContentState extends State<_ActiveOverlayContent> {
  final GlobalKey _followerKey = GlobalKey();
  final GlobalKey _scrimPaintKey = GlobalKey();

  /// One resolver for the State's lifetime (the follower is the same render
  /// object; only its link changes); the painter also reads it at paint time.
  CompositorHintResolver? _resolver;

  /// The target's position (global coordinates). null — the tooltip is not
  /// mounted: on the mount frame the transform is not known yet, and placement
  /// at a zero position would slide off-screen. After the first successful
  /// snapshot the tooltip appears at the right place; this also handles
  /// "target off-screen" — until the target is mounted/visible, there is no
  /// tooltip.
  Offset? _translation;
  bool _pollScheduled = false;

  @override
  void initState() {
    super.initState();
    _schedulePoll();
  }

  @override
  void didUpdateWidget(covariant _ActiveOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-snapshot only when the target changes: another leader's transform
    // is invalid. A step change on the same target keeps the position — the
    // tooltip does not flash (build re-places it for the new step).
    if (oldWidget.link != widget.link) {
      _translation = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final translation = _translation;

        // The tooltip mounts only after an authoritative snapshot (see the
        // field doc).
        Widget? tooltip;
        if (translation != null) {
          final holeLocal = translation & (widget.link.leaderSize ?? Size.zero);
          final ctx = HintTooltipContext(
            actions: widget.actions,
            stepIndex: widget.stepIndex,
            totalSteps: widget.totalSteps,
          );
          // The default tooltip gets the tail (arrow toward the hole); a
          // custom tooltipBuilder owns its look entirely.
          final Widget tooltipChild;
          if (widget.step.tooltipBuilder == null) {
            final defaultTip = DefaultTooltip(step: widget.step, ctx: ctx);
            tooltipChild = widget.theme.showTail
                ? TooltipTail(
                    hole: holeLocal,
                    color: widget.theme.tooltipBackground,
                    child: defaultTip,
                  )
                : defaultTip;
          } else {
            tooltipChild =
                widget.step.tooltipBuilder!(context, widget.step, ctx);
          }
          tooltip = CustomSingleChildLayout(
            delegate: TooltipPlacementDelegate(
              screenLocal: Offset.zero & screen,
              holeLocal: holeLocal,
              position: widget.step.position,
              gap: _kTooltipGap,
              // Keep-in-safe-area: the tooltip never crosses system insets
              // (notch, home indicator).
              safeArea: MediaQuery.paddingOf(context),
            ),
            child: tooltipChild,
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: CompositedTransformFollower(
                key: _followerKey,
                link: widget.link,
                showWhenUnlinked: false,
                child: CustomPaint(
                  key: _scrimPaintKey,
                  painter: ScrimHolePainter(
                    resolver: _resolver ?? const UnpositionedHintResolver(),
                    color: widget.theme.scrimColor,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // Full-screen layout box (getSize = biggest): tooltip buttons are
            // hit-testable anywhere on screen; taps past the tooltip fall
            // through (hitTestSelf = false) onto the scrim → next.
            if (tooltip != null) tooltip,
          ],
        );
      },
    );
  }

  /// Position watcher: reads the compositor transform once per frame (cheap:
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

      _resolver ??= _createResolver();
      final resolver = _resolver;
      if (resolver != null) {
        final position = resolver.resolve();
        if (position is PositionedHint &&
            _translation != position.translation) {
          _translation = position.translation;
          final renderObject =
              _scrimPaintKey.currentContext?.findRenderObject();
          (renderObject as RenderCustomPaint?)?.markNeedsPaint();
          setState(() {}); // tooltip: snapshot/re-placement
        }
      }
      _schedulePoll();
    });
  }

  CompositorHintResolver? _createResolver() {
    final follower = _followerKey.currentContext?.findRenderObject();
    if (follower is! RenderFollowerLayer) return null;
    return CompositorHintResolver(follower);
  }
}
