import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../specs.dart' show TooltipPosition;

const double _kGap = 12;
const double _fallbackPadding = 8.0;

/// Hitting the safe-rect edge exactly is legitimate placement:
/// `Rect.contains` excludes the right/bottom edges, so an epsilon comparison
/// (not contains) does not reject a tooltip exactly fitted to the screen.
const double _edgeEpsilon = 0.5;

/// The area the tooltip must stay inside. Built without `Rect.deflate`:
/// deflate inverts the rect when the insets exceed half the screen; the
/// min/max construction never does.
Rect _safeRectOf(Rect screen, EdgeInsets safeArea) {
  final left =
      math.min(screen.left + safeArea.left, screen.right - safeArea.right);
  final top =
      math.min(screen.top + safeArea.top, screen.bottom - safeArea.bottom);
  final right =
      math.max(screen.left + safeArea.left, screen.right - safeArea.right);
  final bottom =
      math.max(screen.top + safeArea.top, screen.bottom - safeArea.bottom);
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Try order for an explicit [position]: preferred → mirrored → orthogonal.
List<TooltipPosition> _sideOrder(
        TooltipPosition position, Rect safe, Rect hole) =>
    switch (position) {
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
      TooltipPosition.auto => _autoOrder(safe, hole),
    };

/// auto: sides by descending free space inside the safe rect (negative
/// space — the hole sticking out — sinks to the end of the list).
List<TooltipPosition> _autoOrder(Rect safe, Rect hole) {
  final candidates = <(TooltipPosition, double)>[
    (TooltipPosition.bottom, safe.bottom - hole.bottom),
    (TooltipPosition.top, hole.top - safe.top),
    (TooltipPosition.right, safe.right - hole.right),
    (TooltipPosition.left, hole.left - safe.left),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final c in candidates) c.$1];
}

Offset _offsetFor(
  TooltipPosition side,
  Size childSize,
  Rect hole,
  Rect safe,
  double gap,
) {
  switch (side) {
    case TooltipPosition.top:
      return Offset(
        _centerX(childSize.width, hole, safe),
        hole.top - gap - childSize.height,
      );
    case TooltipPosition.bottom:
      return Offset(
        _centerX(childSize.width, hole, safe),
        hole.bottom + gap,
      );
    case TooltipPosition.left:
      return Offset(
        hole.left - gap - childSize.width,
        _centerY(childSize.height, hole, safe),
      );
    case TooltipPosition.right:
      return Offset(
        hole.right + gap,
        _centerY(childSize.height, hole, safe),
      );
    case TooltipPosition.auto:
      throw StateError('auto resolves to concrete sides before layout');
  }
}

/// Centered on the hole along the parallel axis, clamped into the safe rect.
double _centerX(double tooltipWidth, Rect hole, Rect safe) {
  final x = hole.left + (hole.width - tooltipWidth) / 2;
  return _clamp(x, safe.left, safe.right - tooltipWidth);
}

double _centerY(double tooltipHeight, Rect hole, Rect safe) {
  final y = hole.top + (hole.height - tooltipHeight) / 2;
  return _clamp(y, safe.top, safe.bottom - tooltipHeight);
}

/// clamp guarded against \"upper bound below lower bound\" (tooltip wider than
/// the screen): in that case snap to the left/top edge instead of crashing.
double _clamp(double value, double min, double max) =>
    max < min ? min : value.clamp(min, max);

/// Tooltip fully inside the safe rect (edge epsilon) and not overlapping any
/// rect in [avoid] (the holes + already-placed tooltips).
bool _fits(Offset offset, Size childSize, Rect safe, List<Rect> avoid) {
  final rect = offset & childSize;
  if (rect.left < safe.left - _edgeEpsilon ||
      rect.top < safe.top - _edgeEpsilon ||
      rect.right > safe.right + _edgeEpsilon ||
      rect.bottom > safe.bottom + _edgeEpsilon) {
    return false;
  }
  for (final blocked in avoid) {
    if (rect.overlaps(blocked)) return false;
  }
  return true;
}

/// Pure placement core, shared by the single and multi delegates: the offset
/// for a tooltip of [size] around [hole], picking the best fitting side from
/// [position]'s order (preferred → mirrored → orthogonal; auto — by free
/// space) and vetoing placements that overlap [avoid] or leave the safe
/// rect.
///
/// [avoid] must include the tooltip's own anchor [hole] — a tooltip never
/// covers a spotlighted target. For multi-content slots the callers add
/// the already-placed tooltip rects, so slots never overlap each other.
Offset placeTooltip({
  required Rect screen,
  required Rect hole,
  required TooltipPosition position,
  required Size size,
  required EdgeInsets safeArea,
  required List<Rect> avoid,
  double gap = _kGap,
}) {
  final safe = _safeRectOf(screen, safeArea);
  for (final side in _sideOrder(position, safe, hole)) {
    final offset = _offsetFor(side, size, hole, safe, gap);
    if (_fits(offset, size, safe, avoid)) return offset;
  }
  // No side fit (tooltip/hole larger than the safe rect, or every side is
  // blocked) — try the safe-rect corners with a margin (a multi slot does
  // not land on an already-placed tooltip when a corner is free); the last
  // resort is the top-left corner (may still overflow the safe rect
  // bottom/right — nothing fits; the margin keeps it as close as the
  // degenerate case allows).
  final corners = [
    Offset(safe.left + _fallbackPadding, safe.top + _fallbackPadding),
    Offset(
      safe.right - _fallbackPadding - size.width,
      safe.top + _fallbackPadding,
    ),
    Offset(
      safe.left + _fallbackPadding,
      safe.bottom - _fallbackPadding - size.height,
    ),
    Offset(
      safe.right - _fallbackPadding - size.width,
      safe.bottom - _fallbackPadding - size.height,
    ),
  ];
  for (final corner in corners) {
    if (_fits(corner, size, safe, avoid)) return corner;
  }
  return corners.first;
}

/// Tooltip placement relative to its target.
///
/// Side chosen from the **live** target rect: the overlay recreates this
/// delegate with the current `holeLocal` on every movement frame (see
/// overlay_engine.dart), so placement — auto-flip and safe-area included —
/// is recomputed on scroll, not just on step change.
///
/// Keep-in-safe-area: the tooltip stays inside `screenLocal.deflate(safeArea)`
/// (system insets — notch, home indicator). The safe rect is also the space
/// auto-placement counts free space against, so a target under the notch does
/// not pick a side that only \"fits\" in the inset zone.
///
/// Why `CustomSingleChildLayout`: the tooltip size is unknown before layout
/// (text), and the delegate receives it from the framework in
/// [getPositionForChild] (`childSize`) — no manual text measuring (\"no
/// dry-layout\"). The box itself is sized to the screen (default [getSize] =
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
    this.gap = _kGap,
    this.safeArea = EdgeInsets.zero,
    this.extraHoles = const [],
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

  /// Additional spotlighted targets of the step (multi-target steps): the
  /// tooltip must not cover them, only the primary [holeLocal] may be
  /// overlapped (it is the tooltip's anchor). Side selection still counts
  /// free space against the primary hole; extras only veto a placement that
  /// would sit on top of another spotlighted element.
  final List<Rect> extraHoles;

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
    return placeTooltip(
      screen: screenLocal,
      hole: holeLocal,
      position: position,
      size: childSize,
      safeArea: safeArea,
      avoid: [holeLocal, ...extraHoles],
      gap: gap,
    );
  }

  @override
  bool shouldRelayout(covariant TooltipPlacementDelegate oldDelegate) =>
      oldDelegate.screenLocal != screenLocal ||
      oldDelegate.holeLocal != holeLocal ||
      oldDelegate.position != position ||
      oldDelegate.gap != gap ||
      oldDelegate.safeArea != safeArea ||
      !listEquals(oldDelegate.extraHoles, extraHoles);
}

/// Multi-content placement: the primary tooltip plus every extra slot
/// of a step, each placed by the shared [placeTooltip] core — a slot avoids
/// the spotlighted targets AND the already-placed tooltips, so several
/// tooltips around one target never overlap.
///
/// Children are `LayoutId`-wrapped: the primary under [primaryId], extras
/// under [extraId] in order. Placement order matters: the primary first (its
/// side wins the fight for the free space), then the extras one by one (each
/// avoids what is already placed).
class TooltipMultiPlacementDelegate extends MultiChildLayoutDelegate {
  TooltipMultiPlacementDelegate({
    required this.screenLocal,
    required this.holeLocal,
    required this.primaryPosition,
    required this.extraPositions,
    this.gap = _kGap,
    this.safeArea = EdgeInsets.zero,
    this.extraHoles = const [],
  });

  /// Layout id of the primary tooltip child.
  static const String primaryId = 'primary';

  /// Layout id of the extra slot with [index].
  static String extraId(int index) => 'extra_$index';

  final Rect screenLocal;
  final Rect holeLocal;
  final TooltipPosition primaryPosition;

  /// Preferred sides of the extra slots, in order (index == [extraId]).
  final List<TooltipPosition> extraPositions;

  final double gap;
  final EdgeInsets safeArea;

  /// Spotlighted targets of the step besides the primary hole: no slot may
  /// cover them.
  final List<Rect> extraHoles;

  /// The box is the screen (same as the single-tooltip path — tooltip
  /// buttons are hit-testable anywhere on screen, taps past the tooltips
  /// fall through onto the scrim).
  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout(Size size) {
    final avoid = <Rect>[holeLocal, ...extraHoles];

    // Tooltip slots get loose constraints (up to the screen size) — the same
    // as the single-tooltip path; a tight box would stretch them.
    final constraints = BoxConstraints.loose(size);

    // The primary first: its side wins the fight for the free space; the
    // extras then avoid what is already placed.
    if (hasChild(primaryId)) {
      final childSize = layoutChild(primaryId, constraints);
      final offset = placeTooltip(
        screen: screenLocal,
        hole: holeLocal,
        position: primaryPosition,
        size: childSize,
        safeArea: safeArea,
        avoid: avoid,
        gap: gap,
      );
      avoid.add(offset & childSize);
      positionChild(primaryId, offset);
    }

    for (var i = 0; i < extraPositions.length; i++) {
      final id = extraId(i);
      if (!hasChild(id)) continue;
      final childSize = layoutChild(id, constraints);
      final offset = placeTooltip(
        screen: screenLocal,
        hole: holeLocal,
        position: extraPositions[i],
        size: childSize,
        safeArea: safeArea,
        avoid: avoid,
        gap: gap,
      );
      avoid.add(offset & childSize);
      positionChild(id, offset);
    }
  }

  @override
  bool shouldRelayout(covariant TooltipMultiPlacementDelegate oldDelegate) =>
      oldDelegate.screenLocal != screenLocal ||
      oldDelegate.holeLocal != holeLocal ||
      oldDelegate.primaryPosition != primaryPosition ||
      oldDelegate.gap != gap ||
      oldDelegate.safeArea != safeArea ||
      !listEquals(oldDelegate.extraHoles, extraHoles) ||
      !listEquals(oldDelegate.extraPositions, extraPositions);
}
