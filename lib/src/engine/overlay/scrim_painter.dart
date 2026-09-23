import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../specs.dart' show FocusShape;

/// Screen dimming with holes over explicit screen-space rects — the single
/// scrim painter for every mode (active spotlight, rect target, waiting).
///
/// The painter lives in a full-screen global box and cuts [holes] exactly
/// where given. Empty/inverted rects cut nothing (full dim — the waiting
/// mode is simply `holes: const []`); holes outside the canvas contribute
/// nothing.
///
/// ONE mechanism for every shape: the full dim first, then each hole punched
/// with `BlendMode.clear` — plain canvas ops, no boolean path geometry,
/// overlap-correct (clearing the same pixels twice changes nothing, so
/// multi-target holes never double-darken). Only the hole *shape* varies
/// per step (rectangle / circle / rounded rect + padding).
///
/// The dim + punch run inside a `saveLayer`: without isolation `clear`
/// would erase the app content painted beneath this picture (leaving a
/// white box instead of the target). With isolation it erases only the
/// dim — the transparent hole composites over the app on every backend.
///
/// `shouldRepaint` only answers "was the widget rebuilt with a different
/// config?" (holes/color/shape); movement repaints are driven by the
/// caller rebuilding with fresh hole lists (or waiting on `_holeNotifier`).
class RectScrimPainter extends CustomPainter {
  /// Creates a scrim over the screen with [holes] punched through [color].
  const RectScrimPainter({
    required this.holes,
    required this.color,
    this.focusShape = FocusShape.rectangle,
  });

  /// Hole rects in the canvas's own (screen) coordinates, padding already
  /// applied by the caller.
  final List<Rect> holes;

  /// Dim color over the whole screen (its alpha carries the dim level).
  final Color color;

  /// Hole shape — see [holeShape].
  final FocusShape focusShape;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    // Isolated layer: the clear punch must erase only the dim, never the
    // app beneath.
    canvas.saveLayer(screen, Paint());
    canvas.drawRect(screen, Paint()..color = color);
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final h in holes) {
      final shape = holeShape(h, focusShape);
      if (shape == null) continue;
      canvas.drawPath(shape, clear);
    }
    canvas.restore();
  }

  /// One hole shape for [hole]: rectangle / inscribed circle / rounded rect
  /// with clamped corners. Null — an over-shrunk (inverted/empty) rect cuts
  /// nothing. Shared by the painters (drawn with the clear paint) and the
  /// blur clip below, so the shape semantics lives in exactly one place.
  static Path? holeShape(Rect hole, FocusShape focusShape) {
    // Over-shrunk (negative padding beyond the target size) inverts the
    // rect — skip explicitly: an empty hole cuts nothing.
    if (hole.isEmpty) return null;
    final path = Path();
    switch (focusShape) {
      case FocusShape.circle:
        final side = math.max(hole.width, hole.height);
        path.addOval(
          Rect.fromCenter(center: hole.center, width: side, height: side),
        );
      case FocusShape.roundedRect:
        // The corner radius must not exceed the hole itself (tiny targets +
        // negative padding) — clamp to half the shortest side.
        final radius = math.min(12.0, hole.shortestSide / 2);
        path.addRRect(
          RRect.fromRectAndRadius(hole, Radius.circular(radius)),
        );
      case FocusShape.rectangle:
        path.addRect(hole);
    }
    return path;
  }

  /// Clip path for the blur scrim: the screen rect plus the hole shapes in
  /// ONE path with even-odd fill — no boolean ops. The blur
  /// `BackdropFilter` is clipped to it (visible only outside the holes).
  /// Shared by every blur scrim (all anchors, all shapes): only the hole
  /// list differs.
  static Path scrimClipPath(
    Rect screen,
    List<Rect> holes,
    FocusShape focusShape,
  ) {
    final path = Path()..addRect(screen);
    for (final h in holes) {
      final shape = holeShape(h, focusShape);
      if (shape == null) continue;
      path.addPath(shape, Offset.zero);
    }
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldRepaint(covariant RectScrimPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.focusShape != focusShape ||
      !listEquals(oldDelegate.holes, holes);
}
