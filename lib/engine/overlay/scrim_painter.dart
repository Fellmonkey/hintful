import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../position_resolver.dart';

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
/// \"Screen minus holes\" is drawn as **non-overlapping rectangles** around
/// the union of holes ([scrimStrips]), not `Path.combine(difference)`:
/// boolean geometry on a full-screen path is the most expensive part of a
/// frame during movement, plain `drawRect` calls are not (the only per-frame
/// work while scrolling). Strips must not overlap: the scrim color is
/// semi-transparent, and overlapping strips would double-darken.
///
/// The painter is pure: positions are read from [resolvers] at `paint` time
/// (each resolver holds the compositor's current transform), no state is
/// mutated in `paint`. Repaints on movement are triggered externally
/// (`markNeedsPaint` by the position watcher, see overlay_engine.dart);
/// `shouldRepaint` only answers \"was the widget rebuilt with a different
/// config?\" (resolvers/color).
class ScrimHolePainter extends CustomPainter {
  ScrimHolePainter({
    required this.resolvers,
    required this.color,
    this.paintFullScrimWhenUnpositioned = false,
  });

  /// All resolvers of the step's targets; index 0 — the primary (the canvas
  /// anchor). May be temporarily empty (the very first frame before the
  /// position watcher creates the resolvers).
  final List<HintPositionResolver> resolvers;
  final Color color;

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
      Offset.zero & primary.size,
      for (final resolver in resolvers.skip(1))
        if (resolver.resolve()
            case PositionedHint(
              :final translation,
              :final size,
            ))
          (translation - primary.translation) & size,
    ];
    final paint = Paint()..color = color;
    for (final strip in scrimStrips(screenLocal, holes)) {
      canvas.drawRect(strip, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ScrimHolePainter oldDelegate) {
    // Element-wise: the State keeps resolver instances stable per target, so
    // a content-only rebuild (same target set) does not repaint the scrim;
    // a changed target set (new step) does.
    if (oldDelegate.color != color ||
        oldDelegate.paintFullScrimWhenUnpositioned !=
            paintFullScrimWhenUnpositioned ||
        oldDelegate.resolvers.length != resolvers.length) {
      return true;
    }
    for (var i = 0; i < resolvers.length; i++) {
      if (!identical(oldDelegate.resolvers[i], resolvers[i])) return true;
    }
    return false;
  }

  /// Dimming strips around the **union** of [holes] within [screen] — the
  /// complement of the holes, split into non-overlapping rectangles (no
  /// boolean geometry, no overlaps → no double-darkening with a translucent
  /// scrim).
  ///
  /// Algorithm (banding): take the distinct horizontal edges of the screen
  /// and all holes; between each consecutive pair of edges all holes that
  /// intersect the band cut out their x-ranges, merged, and the gaps between
  /// the cuts become strips. Pure function — unit-tested directly. Holes are
  /// clamped into the screen first (a target may stick out beyond an edge);
  /// a hole fully outside the screen contributes nothing.
  static List<Rect> scrimStrips(Rect screen, List<Rect> holes) {
    if (holes.isEmpty) return [screen];

    final clamped = <Rect>[];
    for (final hole in holes) {
      final left = math.max(hole.left, screen.left);
      final top = math.max(hole.top, screen.top);
      final right = math.min(hole.right, screen.right);
      final bottom = math.min(hole.bottom, screen.bottom);
      if (right <= left || bottom <= top) continue; // fully outside
      clamped.add(Rect.fromLTRB(left, top, right, bottom));
    }
    if (clamped.isEmpty) return [screen]; // everything is covered — no strips

    final edges = <double>{screen.top, screen.bottom};
    for (final hole in clamped) {
      edges.add(hole.top);
      edges.add(hole.bottom);
    }
    final sorted = edges.toList()..sort();

    final strips = <Rect>[];
    for (var i = 0; i + 1 < sorted.length; i++) {
      final y0 = sorted[i];
      final y1 = sorted[i + 1];
      if (y1 - y0 <= 0) continue;
      // Holes intersecting this band, by their x-range, sorted by left edge.
      final cuts = <(double, double)>[
        for (final hole in clamped)
          if (hole.top <= y0 && hole.bottom >= y1) (hole.left, hole.right),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      if (cuts.isEmpty) {
        strips.add(Rect.fromLTRB(screen.left, y0, screen.right, y1));
        continue;
      }
      // Merge overlapping cuts, emitting the scrim gaps between them.
      var cursor = screen.left;
      var cutStart = cuts.first.$1;
      var cutEnd = cuts.first.$2;
      for (final (start, end) in cuts.skip(1)) {
        if (start <= cutEnd) {
          cutEnd = math.max(cutEnd, end);
        } else {
          if (cutStart > cursor) {
            strips.add(Rect.fromLTRB(cursor, y0, cutStart, y1));
          }
          cursor = cutEnd;
          cutStart = start;
          cutEnd = end;
        }
      }
      if (cutStart > cursor) {
        strips.add(Rect.fromLTRB(cursor, y0, cutStart, y1));
      }
      if (screen.right > cutEnd) {
        strips.add(Rect.fromLTRB(cutEnd, y0, screen.right, y1));
      }
    }
    return strips;
  }
}
