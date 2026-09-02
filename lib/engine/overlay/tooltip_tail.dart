import 'package:flutter/widgets.dart';

/// Which edge of the tooltip the tail points from, toward the target.
enum TailSide { top, bottom, left, right }

/// Sub-pixel tolerance: the tooltip rect comes from the compositor transform
/// (float noise ~1e-16 is amplified by ancestor matrices), so an exact
/// comparison could lose the side on a hairline overlap. 0.5 px is also the
/// placement delegate's edge epsilon — consistent.
const double _kEpsilon = 0.5;

/// The tooltip's edge facing the [hole], derived purely from geometry.
///
/// The side is computed from the *actual* rects at paint time, so it always
/// agrees with the real placement — including the auto-flip on scroll (no
/// side needs to be stored by the placement delegate or threaded through the
/// layout phase, where the child's final offset is not known yet).
///
/// Returns null when the tooltip overlaps the hole in both axes — the
/// degenerate \"nothing fits\" fallback corner: an arrow would point at
/// nothing, so no tail is drawn.
TailSide? tailSideFor(Rect tooltip, Rect hole) {
  if (tooltip.bottom <= hole.top + _kEpsilon) return TailSide.bottom;
  if (tooltip.top >= hole.bottom - _kEpsilon) return TailSide.top;
  if (tooltip.right <= hole.left + _kEpsilon) return TailSide.right;
  if (tooltip.left >= hole.right - _kEpsilon) return TailSide.left;
  return null;
}

/// Default tail sizes (kept as constants; the theme only toggles presence).
const double _kTailLength = 10.0;
const double _kTailWidth = 14.0;

/// Triangle of the tail in tooltip-local coordinates.
///
/// [tooltip] — the tooltip's rect in the same (global) space as [hole], to
/// derive the hole's center in local coordinates; [tooltipSize] — the
/// painter's canvas size (== the tooltip's size). The base sits on the
/// tooltip's edge (half a pixel inside, so the opaque tooltip surface covers
/// the seam); the apex extends [length] beyond it, toward the hole.
Path tailPath({
  required TailSide side,
  required Size tooltipSize,
  required Rect hole,
  required Rect tooltip,
  double length = _kTailLength,
  double width = _kTailWidth,
}) {
  final half = width / 2;
  final path = Path();
  switch (side) {
    case TailSide.bottom:
      final cx =
          _clampCenter(hole.center.dx - tooltip.left, tooltipSize.width, half);
      path
        ..moveTo(cx - half, tooltipSize.height - 0.5)
        ..lineTo(cx + half, tooltipSize.height - 0.5)
        ..lineTo(cx, tooltipSize.height + length)
        ..close();
    case TailSide.top:
      final cx =
          _clampCenter(hole.center.dx - tooltip.left, tooltipSize.width, half);
      path
        ..moveTo(cx - half, 0.5)
        ..lineTo(cx + half, 0.5)
        ..lineTo(cx, -length)
        ..close();
    case TailSide.left:
      final cy =
          _clampCenter(hole.center.dy - tooltip.top, tooltipSize.height, half);
      path
        ..moveTo(0.5, cy - half)
        ..lineTo(0.5, cy + half)
        ..lineTo(-length, cy)
        ..close();
    case TailSide.right:
      final cy =
          _clampCenter(hole.center.dy - tooltip.top, tooltipSize.height, half);
      path
        ..moveTo(tooltipSize.width - 0.5, cy - half)
        ..lineTo(tooltipSize.width - 0.5, cy + half)
        ..lineTo(tooltipSize.width + length, cy)
        ..close();
  }
  return path;
}

/// The hole's center along the tooltip's parallel axis, clamped so the
/// triangle base stays within the tooltip edge; a degenerate tiny tooltip
/// (edge shorter than the base) gets a centered base instead of an off-edge
/// one.
double _clampCenter(double value, double extent, double halfWidth) {
  final min = halfWidth;
  final max = extent - halfWidth;
  if (max < min) return extent / 2;
  return value.clamp(min, max);
}

/// Paints the tail as part of the tooltip surface.
///
/// The tooltip's global position is read at **paint** time from [positionKey]
/// (the tooltip's render object): by then layout is final, so the geometry
/// always matches the actual placement — no snapshot, no canvas-matrix
/// introspection (which would be polluted by the device pixel ratio).
///
/// The hole is read **live** from [holeOf] at paint time: the tooltip
/// content is cached across movement frames (see overlay_engine), so a
/// painted-with-stale-hole tail would keep pointing at the target's old
/// position while the scrim/tooltip follow it. Repainting is driven by the
/// tooltip's own repaint on movement (layout offset change → paint) — the
/// painter then reads both the current tooltip position and the current
/// hole.
class TooltipTailPainter extends CustomPainter {
  TooltipTailPainter({
    required this.positionKey,
    required this.holeOf,
    required this.color,
    this.tailLength = _kTailLength,
    this.tailWidth = _kTailWidth,
  });

  /// Key of the tooltip's render object (the painter's child subtree) — the
  /// source of the tooltip's global position.
  final GlobalKey positionKey;

  /// The target (scrim hole) rect in global overlay coordinates, resolved at
  /// paint time (the hole moves with the target on scroll).
  final Rect Function() holeOf;

  /// Filled with the tooltip's background color — the tail looks like part
  /// of the same surface.
  final Color color;

  final double tailLength;
  final double tailWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final render = positionKey.currentContext?.findRenderObject();
    if (render is! RenderBox) return;
    final tooltip = render.localToGlobal(Offset.zero) & size;
    final side = tailSideFor(tooltip, holeOf());
    if (side == null) return;
    canvas.drawPath(
      tailPath(
        side: side,
        tooltipSize: size,
        hole: holeOf(),
        tooltip: tooltip,
        length: tailLength,
        width: tailWidth,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant TooltipTailPainter oldDelegate) =>
      oldDelegate.positionKey != positionKey ||
      oldDelegate.holeOf != holeOf ||
      oldDelegate.color != color ||
      oldDelegate.tailLength != tailLength ||
      oldDelegate.tailWidth != tailWidth;
}

/// The tail (arrow toward the target) rendered behind the default tooltip.
///
/// Engine-internal: wraps [DefaultTooltip] in overlay_engine.dart — the
/// public tooltip widget stays hole-agnostic (it does not know where the
/// target is). Custom tooltips (`tooltipBuilder`) own their look entirely —
/// no tail is added to them.
class TooltipTail extends StatefulWidget {
  const TooltipTail({
    super.key,
    required this.holeOf,
    required this.color,
    required this.child,
  });

  /// The target (scrim hole) rect in global overlay coordinates, resolved at
  /// paint time (see [TooltipTailPainter.holeOf]).
  final Rect Function() holeOf;

  final Color color;
  final Widget child;

  @override
  State<TooltipTail> createState() => _TooltipTailState();
}

class _TooltipTailState extends State<TooltipTail> {
  // Owned by the State (not created in build) so the key survives rebuilds
  // and always refers to the current child render object.
  final GlobalKey _positionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: TooltipTailPainter(
        positionKey: _positionKey,
        holeOf: widget.holeOf,
        color: widget.color,
      ),
      child: KeyedSubtree(key: _positionKey, child: widget.child),
    );
  }
}
