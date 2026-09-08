import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../position_resolver.dart';
import '../specs.dart' show FocusShape;

/// Screen dimming with \"holes\" over the step's targets (one or more).
///
/// The painter lives **inside** a `CompositedTransformFollower`, so its canvas
/// origin is the primary target's top-left corner and the primary hole is
/// always at local (0,0) with the size `leaderSize`: its on-screen position
/// is updated by the compositor's transform. The adaptive part is the screen
/// in local coordinates: `screenLocal = screenRect.translate(-tx, -ty)`.
///
/// [resolvers] index 0 is the primary — the one whose follower hosts this
/// painter (the canvas anchor). The rest are the step's additional targets,
/// each resolved through its own follower; their holes are translated into
/// this canvas's space (`theirTranslation - primaryTranslation`). A resolver
/// that yields [UnpositionedHint] simply contributes no hole.
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
/// The painter is pure: positions are read from [resolvers] at `paint` time
/// (each resolver holds the compositor's current transform), no state is
/// mutated in `paint`. Repaints on movement are triggered externally
/// (`markNeedsPaint` by the position watcher, see overlay_engine.dart);
/// `shouldRepaint` only answers \"was the widget rebuilt with a different
/// config?\" (resolvers/color).
class ScrimHolePainter extends CustomPainter {
  const ScrimHolePainter({
    required this.resolvers,
    required this.color,
    this.paintFullScrimWhenUnpositioned = false,
    this.focusShape = FocusShape.rectangle,
    this.focusPadding = 4.0,
  });

  /// All resolvers of the step's targets; index 0 — the primary (the canvas
  /// anchor). May be temporarily empty (the very first frame before the
  /// position watcher creates the resolvers).
  final List<HintPositionResolver> resolvers;
  final Color color;
  final FocusShape focusShape;
  final double focusPadding;

  /// true — the waiting mode: the primary is not in the tree at all, dim the
  /// whole screen (no hole). false — the active mode: an unpositioned
  /// primary means "position not known yet" (first frame / a new target's
  /// follower not composed), and the painter draws NOTHING — a full rect
  /// here would be anchored at the target's position and flash a misaligned
  /// partial dim before the hole appears (the "zone appears, but not at full
  /// coverage" artifact).
  final bool paintFullScrimWhenUnpositioned;

  @override
  void paint(Canvas canvas, Size size) {
    final primary = resolvers.isEmpty ? null : resolvers.first.resolve();
    if (primary is! PositionedHint) {
      if (paintFullScrimWhenUnpositioned) {
        canvas.drawRect(Offset.zero & size, Paint()..color = color);
      }
      return;
    }

    final screenLocal = Rect.fromLTWH(
      -primary.translation.dx,
      -primary.translation.dy,
      size.width,
      size.height,
    );
    final holes = <Rect>[
      (Offset.zero & primary.size).inflate(focusPadding),
      for (final resolver in resolvers.skip(1))
        if (resolver.resolve()
            case PositionedHint(
              :final translation,
              :final size,
            ))
          ((translation - primary.translation) & size).inflate(focusPadding),
    ];
    // Isolated layer: BlendMode.clear below must erase only the dim —
    // never the app painted beneath this picture.
    canvas.saveLayer(screenLocal, Paint());
    canvas.drawRect(screenLocal, Paint()..color = color);
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
  /// Shared by every blur scrim (follower-anchored and rect-anchored, all
  /// shapes): only the hole list differs.
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
  bool shouldRepaint(covariant ScrimHolePainter oldDelegate) {
    if (oldDelegate.color != color ||
        oldDelegate.focusShape != focusShape ||
        oldDelegate.focusPadding != focusPadding ||
        oldDelegate.paintFullScrimWhenUnpositioned != paintFullScrimWhenUnpositioned ||
        oldDelegate.resolvers.length != resolvers.length) {
      return true;
    }
    for (var i = 0; i < resolvers.length; i++) {
      if (!identical(oldDelegate.resolvers[i], resolvers[i])) return true;
    }
    return false;
  }
}

/// Screen dimming with holes at explicit screen-space rects — the
/// `targetRect` path ([HintStep.targetRect]), where there is no
/// `CompositedTransformTarget` leader to anchor a follower painter to.
///
/// Unlike [ScrimHolePainter] (whose canvas rides on the primary target and
/// reads live compositor transforms), this painter lives in a full-screen
/// global box and cuts [holes] exactly where given — static coordinates, no
/// movement tracking, no resolvers. Empty/inverted rects cut nothing (full
/// dim); holes outside the canvas contribute nothing.
class RectScrimPainter extends CustomPainter {
  const RectScrimPainter({
    required this.holes,
    required this.color,
    this.focusShape = FocusShape.rectangle,
  });

  /// Hole rects in the canvas's own (screen) coordinates, padding already
  /// applied by the caller.
  final List<Rect> holes;
  final Color color;

  /// Hole shape — same semantics as [ScrimHolePainter.holeShape].
  final FocusShape focusShape;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    // Isolated layer (see ScrimHolePainter): the clear punch must erase
    // only the dim, never the app beneath.
    canvas.saveLayer(screen, Paint());
    canvas.drawRect(screen, Paint()..color = color);
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final h in holes) {
      final shape = ScrimHolePainter.holeShape(h, focusShape);
      if (shape == null) continue;
      canvas.drawPath(shape, clear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RectScrimPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.focusShape != focusShape ||
      !listEquals(oldDelegate.holes, holes);
}
