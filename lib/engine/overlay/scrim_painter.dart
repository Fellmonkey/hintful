import 'package:flutter/widgets.dart';

import '../position_resolver.dart';

/// Screen dimming with a "hole" over the target.
///
/// The painter lives **inside** a `CompositedTransformFollower`, so its canvas
/// origin is the target's top-left corner and the hole is always at local
/// (0,0) with the size `leaderSize`: its on-screen position is updated by the
/// compositor's transform. The adaptive part is the screen in local
/// coordinates: `screenLocal = screenRect.translate(-tx, -ty)`.
///
/// "Screen minus hole" is drawn as **four rectangles** around the hole, not
/// `Path.combine(difference)`: boolean geometry on a full-screen path is the
/// most expensive part of a frame during movement, four `drawRect` calls are
/// not (the only per-frame work while scrolling).
///
/// The painter is pure: position is read from [resolver] at `paint` time (the
/// resolver holds the compositor's current transform), no state is mutated in
/// `paint`. Repaints on movement are triggered externally (`markNeedsPaint`
/// by the position watcher, see overlay_engine.dart); `shouldRepaint` only
/// answers "was the widget rebuilt with a different config?" (resolver/color).
class ScrimHolePainter extends CustomPainter {
  ScrimHolePainter({required this.resolver, required this.color});

  final TargetPositionResolver resolver;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final position = resolver.resolve();
    if (position is! PositionedTarget) {
      // Target not mounted (waiting mode): full scrim without a hole.
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
      return;
    }

    final screenLocal = Rect.fromLTWH(
      -position.translation.dx,
      -position.translation.dy,
      size.width,
      size.height,
    );
    final hole = Rect.fromLTWH(
      0,
      0,
      position.size.width,
      position.size.height,
    );
    final paint = Paint()..color = color;
    for (final strip in scrimStrips(screenLocal, hole)) {
      canvas.drawRect(strip, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ScrimHolePainter oldDelegate) =>
      oldDelegate.resolver != resolver || oldDelegate.color != color;

  /// Dimming strips around [hole] within [screen] (no boolean geometry).
  ///
  /// Pure function — unit-tested directly. [hole] may partially extend
  /// outside [screen] (target near a screen edge): strips are clamped into
  /// the screen and degenerate (zero-size) ones are dropped.
  static List<Rect> scrimStrips(Rect screen, Rect hole) {
    final top = hole.top.clamp(screen.top, screen.bottom);
    final bottom = hole.bottom.clamp(screen.top, screen.bottom);
    final left = hole.left.clamp(screen.left, screen.right);
    final right = hole.right.clamp(screen.left, screen.right);

    final strips = <Rect>[
      // Top and bottom strips span the full screen width.
      if (top > screen.top)
        Rect.fromLTRB(screen.left, screen.top, screen.right, top),
      if (screen.bottom > bottom)
        Rect.fromLTRB(screen.left, bottom, screen.right, screen.bottom),
      // Side strips between the hole's top and bottom.
      if (left > screen.left) Rect.fromLTRB(screen.left, top, left, bottom),
      if (screen.right > right) Rect.fromLTRB(right, top, screen.right, bottom),
    ];
    return strips;
  }
}
