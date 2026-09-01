import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../widgets/default_tooltip.dart';
import '../controller.dart' show ShowcaseController, TourOverlayHost;
import '../diagnostics.dart';
import '../machine.dart';
import '../position_resolver.dart';
import '../registry.dart';
import '../specs.dart';
import '../theme/showcase_theme.dart';
import 'scrim_painter.dart';
import 'tooltip_placement.dart';

const _kTooltipGap = 12.0;
const _kWaitingText = 'Preparing…';

/// Standard render-mechanics wiring: the engine over [registry] (defaults to
/// the registry singleton — zero-config).
///
/// The only public entry into render mechanics, for `ShowcaseController`:
///
/// ```dart
/// final controller = ShowcaseController(overlayHostBuilder: defaultOverlayHost());
/// ```
///
/// The engine itself and its internals (scrim, placement delegate) stay
/// hidden: they can change without breaking, while this contract is stable.
TourOverlayHost Function(ShowcaseController) defaultOverlayHost({
  TargetRegistry? registry,
}) {
  return (controller) => TourOverlayEngine(
        registry: registry ?? TargetRegistry.defaultInstance,
        input: controller,
      );
}

/// Tour render mechanics: mounts a single `OverlayEntry`, draws the scrim
/// hole via `CompositedTransformFollower` (target position from the
/// compositor), places the tooltip, handles tap-on-overlay and keyboard.
///
/// Implements the [TourOverlayHost] contract from controller.dart: the
/// controller does not know what the overlay looks like or where the
/// `OverlayState` comes from — the engine captures it itself (the root
/// overlay of the first registered target), or receives it explicitly via
/// `overlay` for fully-deferred scenarios (zero mounted targets). User input
/// (next/skip/finish) goes into [TourActions] — the controller implements it.
class TourOverlayEngine implements TourOverlayHost {
  TourOverlayEngine({
    required TargetRegistry registry,
    required TourActions input,
    OverlayState? overlay,
    HintDiagnosticsHandler? diagnostics,
  })  : _registry = registry,
        _input = input,
        _overlay = overlay,
        _diagnostics = diagnostics;

  final TargetRegistry _registry;
  final TourActions _input;
  final HintDiagnosticsHandler? _diagnostics;
  OverlayState? _overlay;
  OverlayEntry? _entry;
  TourState? _pendingState;
  bool _disposed = false;

  @override
  void update(TourState state) {
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
      TourWaiting(:final targetId) => targetId,
      TourActive(:final targetId) => targetId,
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
        return _TourOverlayView(
          state: state,
          registry: _registry,
          input: _input,
        );
      },
    );
  }
}

// ──────────────────────── entry content ────────────────────────

class _TourOverlayView extends StatefulWidget {
  const _TourOverlayView({
    required this.state,
    required this.registry,
    required this.input,
  });

  final TourState state;
  final TargetRegistry registry;
  final TourActions input;

  @override
  State<_TourOverlayView> createState() => _TourOverlayViewState();
}

class _TourOverlayViewState extends State<_TourOverlayView> {
  final FocusScopeNode _scopeNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    // `autofocus` on a FocusScope registers a node INSIDE the scope and does
    // not focus the scope itself — in an app with a Navigator, focus stays on
    // the route's scope (_ModalScopeState) and Esc/Tab/Enter never arrive
    // (worked in a bare Overlay, not in MaterialApp). An explicit
    // requestFocus post-frame after the entry mounts wins.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scopeNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scopeNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.input.skip();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab ||
        event.logicalKey == LogicalKeyboardKey.enter) {
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
            scrimColor: hintTheme.scrimColor,
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
  Widget _buildWaitingMode(ShowcaseTheme theme) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: ScrimHolePainter(
              resolver: const UnlinkedTargetResolver(),
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
    TargetRegistration registration,
    StepSpec step, {
    required int stepIndex,
    required int totalSteps,
    required Color scrimColor,
  }) {
    return _ActiveOverlayContent(
      link: registration.link,
      step: step,
      stepIndex: stepIndex,
      totalSteps: totalSteps,
      actions: widget.input,
      scrimColor: scrimColor,
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
///   Cost: the tooltip follows scrolls via snapshot + `setState` (the
///   watcher) instead of the transform — a one-frame lag. Fully recomputing
///   placement on scroll is follow-up work.
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
    required this.scrimColor,
  });

  final LayerLink link;
  final StepSpec step;
  final int stepIndex;
  final int totalSteps;
  final TourActions actions;
  final Color scrimColor;

  @override
  State<_ActiveOverlayContent> createState() => _ActiveOverlayContentState();
}

class _ActiveOverlayContentState extends State<_ActiveOverlayContent> {
  final GlobalKey _followerKey = GlobalKey();
  final GlobalKey _scrimPaintKey = GlobalKey();

  /// One resolver for the State's lifetime (the follower is the same render
  /// object; only its link changes); the painter also reads it at paint time.
  CompositorPositionResolver? _resolver;

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
          final ctx = StepTooltipContext(
            actions: widget.actions,
            stepIndex: widget.stepIndex,
            totalSteps: widget.totalSteps,
          );
          tooltip = CustomSingleChildLayout(
            delegate: TooltipPlacementDelegate(
              screenLocal: Offset.zero & screen,
              holeLocal: translation & (widget.link.leaderSize ?? Size.zero),
              position: widget.step.position,
              gap: _kTooltipGap,
            ),
            child: widget.step.tooltipBuilder != null
                ? widget.step.tooltipBuilder!(context, widget.step, ctx)
                : DefaultTooltip(step: widget.step, ctx: ctx),
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
                    resolver: _resolver ?? const UnlinkedTargetResolver(),
                    color: widget.scrimColor,
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
        if (position is PositionedTarget &&
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

  CompositorPositionResolver? _createResolver() {
    final follower = _followerKey.currentContext?.findRenderObject();
    if (follower is! RenderFollowerLayer) return null;
    return CompositorPositionResolver(follower);
  }
}
