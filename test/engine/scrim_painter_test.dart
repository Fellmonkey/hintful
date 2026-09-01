import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/engine/position_resolver.dart';

/// Fake resolver: a deterministic position (or Unlinked).
class _FakeResolver implements TargetPositionResolver {
  _FakeResolver(this.position);

  final TargetPosition position;

  @override
  TargetPosition resolve() => position;
}

void main() {
  const screen = Rect.fromLTWH(0, 0, 800, 600);

  group('scrimStrips (4 rectangles around the hole)', () {
    test('hole in the center — 4 strips without overlaps', () {
      const hole = Rect.fromLTWH(300, 200, 200, 100);
      final strips = ScrimHolePainter.scrimStrips(screen, hole);

      expect(strips, hasLength(4));
      // Top/bottom span the whole screen width; left/right — the hole height.
      expect(strips, contains(const Rect.fromLTWH(0, 0, 800, 200)));
      expect(strips, contains(const Rect.fromLTWH(0, 300, 800, 300)));
      expect(strips, contains(const Rect.fromLTWH(0, 200, 300, 100)));
      expect(strips, contains(const Rect.fromLTWH(500, 200, 300, 100)));
      // No two strips overlap (a shared edge is fine).
      for (var i = 0; i < strips.length; i++) {
        for (var j = i + 1; j < strips.length; j++) {
          final a = strips[i].deflate(0.01);
          final b = strips[j].deflate(0.01);
          expect(a.overlaps(b), isFalse, reason: '$a and $b overlap');
        }
      }
    });

    test('hole at the left edge — 3 strips (no left one)', () {
      const hole = Rect.fromLTWH(0, 200, 200, 100);
      final strips = ScrimHolePainter.scrimStrips(screen, hole);
      expect(strips, hasLength(3));
      expect(
        strips.every((r) => r.left >= 0),
        isTrue,
        reason: 'no strip is left of the screen',
      );
    });

    test('hole partially above the screen — strips clamped, none degenerate',
        () {
      // The hole starts above the screen: hole.top = -50.
      const hole = Rect.fromLTWH(300, -50, 200, 400); // bottom = 350
      final strips = ScrimHolePainter.scrimStrips(screen, hole);
      // No top strip (the hole covers the top), sides run from 0 to 350.
      expect(strips, hasLength(3));
      expect(strips, contains(const Rect.fromLTWH(0, 350, 800, 250))); // bottom
      expect(strips, contains(const Rect.fromLTWH(0, 0, 300, 350))); // left
      expect(strips, contains(const Rect.fromLTWH(500, 0, 300, 350))); // right
      for (final r in strips) {
        expect(r.height > 0 && r.width > 0, isTrue,
            reason: 'degenerate strip: $r');
      }
    });

    test('hole bigger than the screen — no scrim (nothing to darken)', () {
      const hole = Rect.fromLTWH(-100, -100, 1000, 800);
      final strips = ScrimHolePainter.scrimStrips(screen, hole);
      expect(strips, isEmpty);
    });

    test('hole exactly the screen — no scrim', () {
      final strips = ScrimHolePainter.scrimStrips(screen, screen);
      expect(strips, isEmpty);
    });
  });

  group('ScrimHolePainter', () {
    test('shouldRepaint: only when the resolver or color changes', () {
      final resolver = _FakeResolver(const PositionedTarget(
        translation: Offset.zero,
        size: Size(10, 10),
      ));
      final a =
          ScrimHolePainter(resolver: resolver, color: const Color(0xFF000000));
      final same = ScrimHolePainter(
        resolver: resolver,
        color: const Color(0xFF000000),
      );
      final otherColor = ScrimHolePainter(
        resolver: resolver,
        color: const Color(0x80000000),
      );
      final otherResolver = _FakeResolver(const UnlinkedTarget());
      final other = ScrimHolePainter(
        resolver: otherResolver,
        color: const Color(0xFF000000),
      );

      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(otherColor), isTrue);
      expect(a.shouldRepaint(other), isTrue);
    });
  });
}
