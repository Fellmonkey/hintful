import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../specs.dart' show TooltipPosition;

/// Tooltip placement relative to its target.
///
/// Side chosen from the **live** target rect: the overlay recreates this
/// delegate with the current `holeLocal` on every movement frame (see
/// overlay_engine.dart), so placement — auto-flip and safe-area included —
/// is recomputed on scroll, not just on step change. Multi-content
/// collisions are follow-up work.
///
/// Keep-in-safe-area: the tooltip stays inside `screenLocal.deflate(safeArea)`
/// (system insets — notch, home indicator). The safe rect is also the space
/// auto-placement counts free space against, so a target under the notch does
/// not pick a side that only "fits" in the inset zone.
///
/// Why `CustomSingleChildLayout`: the tooltip size is unknown before layout
/// (text), and the delegate receives it from the framework in
/// [getPositionForChild] (`childSize`) — no manual text measuring ("no
/// dry-layout"). The box itself is sized to the screen (default [getSize] =
/// `constraints.biggest`), so the tooltip buttons are hit-testable anywhere
/// on screen, and taps past the tooltip fall through (`hitTestSelf` = false)
/// onto the scrim.
///
/// Side selection: try the preferred side; if it does not fit the safe rect —
/// mirror (bottom↔top, left↔right); still not fitting — the other sides;
/// last resort (tooltip or hole larger than the screen) — a safe-rect corner
/// with a margin.
class TooltipPlacementDelegate extends SingleChildLayoutDelegate {
  TooltipPlacementDelegate({
    required this.screenLocal,
    required this.holeLocal,
    required this.position,
    this.gap = 12,
    this.safeArea = EdgeInsets.zero,
  });

  /// The screen in the tooltip layer's coordinates (global here — the
  /// tooltip lives in the full-screen overlay layer, see overlay_engine.dart).
  final Rect screenLocal;

  /// The target (scrim hole) rect in the same coordinates:
  /// `translation & leaderSize`.
  final Rect holeLocal;

  /// Preferred side; [TooltipPosition.auto] — the side with the most free
  /// space between the hole and the screen edge.
  final TooltipPosition position;

  /// Gap between the tooltip and the hole.
  final double gap;

  /// System insets (`MediaQuery.padding` — notch, home indicator): the
  /// tooltip stays inside `screenLocal.deflate(safeArea)`. Zero — the whole
  /// screen is usable (the previous behavior).
  final EdgeInsets safeArea;

  /// The area the tooltip must stay inside. Built without `Rect.deflate`:
  /// deflate inverts the rect when the insets exceed half the screen; the
  /// min/max construction never does.
  Rect get _safeRect {
    final left = math.min(
        screenLocal.left + safeArea.left, screenLocal.right - safeArea.right);
    final top = math.min(
        screenLocal.top + safeArea.top, screenLocal.bottom - safeArea.bottom);
    final right = math.max(
        screenLocal.left + safeArea.left, screenLocal.right - safeArea.right);
    final bottom = math.max(
        screenLocal.top + safeArea.top, screenLocal.bottom - safeArea.bottom);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static const double _fallbackPadding = 8.0;

  /// Hitting the screen edge exactly is legitimate placement: `Rect.contains`
  /// excludes the right/bottom edges, so an epsilon comparison (not contains)
  /// does not reject a tooltip exactly fitted to the screen.
  static const double _edgeEpsilon = 0.5;

  /// The tooltip gets loose constraints (up to screen size) and picks its own
  /// size; a tight box would stretch it over the whole screen.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  /// `size` — the layout box size (= the screen, see class doc);
  /// `childSize` — the tooltip's actual size after layout.
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    assert(
      size.width == screenLocal.width && size.height == screenLocal.height,
      'layout box must be the screen (screenLocal.size == box size)',
    );
    for (final side in _sideOrder) {
      final offset = _offsetFor(side, childSize);
      if (_fits(offset, childSize)) return offset;
    }
    // No side fit (tooltip/hole larger than the safe rect) — a safe-rect
    // corner with a margin (may still overflow the safe rect bottom/right —
    // nothing fits; the margin keeps it as close to the top-left corner as
    // the degenerate case allows).
    return Offset(
      _safeRect.left + _fallbackPadding,
      _safeRect.top + _fallbackPadding,
    );
  }

  @override
  bool shouldRelayout(covariant TooltipPlacementDelegate oldDelegate) =>
      oldDelegate.screenLocal != screenLocal ||
      oldDelegate.holeLocal != holeLocal ||
      oldDelegate.position != position ||
      oldDelegate.gap != gap ||
      oldDelegate.safeArea != safeArea;

  // ──────────────────────────── internals ────────────────────────────

  /// Try order: preferred → mirrored → orthogonal sides.
  List<TooltipPosition> get _sideOrder => switch (position) {
        TooltipPosition.bottom => const [
            TooltipPosition.bottom,
            TooltipPosition.top,
            TooltipPosition.right,
            TooltipPosition.left,
          ],
        TooltipPosition.top => const [
            TooltipPosition.top,
            TooltipPosition.bottom,
            TooltipPosition.right,
            TooltipPosition.left,
          ],
        TooltipPosition.right => const [
            TooltipPosition.right,
            TooltipPosition.left,
            TooltipPosition.bottom,
            TooltipPosition.top,
          ],
        TooltipPosition.left => const [
            TooltipPosition.left,
            TooltipPosition.right,
            TooltipPosition.bottom,
            TooltipPosition.top,
          ],
        TooltipPosition.auto => _autoOrder,
      };

  /// auto: sides by descending free space inside the safe rect (negative
  /// space — the hole sticking out — sinks to the end of the list).
  List<TooltipPosition> get _autoOrder {
    final safe = _safeRect;
    final candidates = <(TooltipPosition, double)>[
      (TooltipPosition.bottom, safe.bottom - holeLocal.bottom),
      (TooltipPosition.top, holeLocal.top - safe.top),
      (TooltipPosition.right, safe.right - holeLocal.right),
      (TooltipPosition.left, holeLocal.left - safe.left),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final c in candidates) c.$1];
  }

  Offset _offsetFor(TooltipPosition side, Size childSize) {
    switch (side) {
      case TooltipPosition.top:
        return Offset(
          _centerX(childSize.width),
          holeLocal.top - gap - childSize.height,
        );
      case TooltipPosition.bottom:
        return Offset(
          _centerX(childSize.width),
          holeLocal.bottom + gap,
        );
      case TooltipPosition.left:
        return Offset(
          holeLocal.left - gap - childSize.width,
          _centerY(childSize.height),
        );
      case TooltipPosition.right:
        return Offset(
          holeLocal.right + gap,
          _centerY(childSize.height),
        );
      case TooltipPosition.auto:
        throw StateError('auto resolves to concrete sides before layout');
    }
  }

  /// Centered on the hole along the parallel axis, clamped into the safe rect.
  double _centerX(double tooltipWidth) {
    final safe = _safeRect;
    final x = holeLocal.left + (holeLocal.width - tooltipWidth) / 2;
    return _clamp(x, safe.left, safe.right - tooltipWidth);
  }

  double _centerY(double tooltipHeight) {
    final safe = _safeRect;
    final y = holeLocal.top + (holeLocal.height - tooltipHeight) / 2;
    return _clamp(y, safe.top, safe.bottom - tooltipHeight);
  }

  /// clamp guarded against "upper bound below lower bound" (tooltip wider than
  /// the screen): in that case snap to the left/top edge instead of crashing.
  static double _clamp(double value, double min, double max) =>
      max < min ? min : value.clamp(min, max);

  /// Tooltip fully inside the safe rect (edge epsilon) and not overlapping
  /// the hole.
  bool _fits(Offset offset, Size childSize) {
    final safe = _safeRect;
    final rect = offset & childSize;
    if (rect.left < safe.left - _edgeEpsilon ||
        rect.top < safe.top - _edgeEpsilon ||
        rect.right > safe.right + _edgeEpsilon ||
        rect.bottom > safe.bottom + _edgeEpsilon) {
      return false;
    }
    return !rect.overlaps(holeLocal);
  }
}
