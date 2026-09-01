import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/engine/position_resolver.dart';

/// Fake resolver: a deterministic position (or Unpositioned).
class _FakeResolver implements HintPositionResolver {
  _FakeResolver(this.position);

  final HintPosition position;

  @override
  HintPosition resolve() => position;
}

void main() {
  const screen = Rect.fromLTWH(0, 0, 800, 600);

  /// Strips must never overlap (a translucent scrim would double-darken).
  void expectNoOverlaps(List<Rect> strips) {
    for (var i = 0; i < strips.length; i++) {
      for (var j = i + 1; j < strips.length; j++) {
        final a = strips[i].deflate(0.01);
        final b = strips[j].deflate(0.01);
        expect(a.overlaps(b), isFalse, reason: '$a and $b overlap');
      }
    }
  }

  group('scrimStrips (rectangles around the union of holes)', () {
    test('one hole in the center — 4 strips without overlaps', () {
      const hole = Rect.fromLTWH(300, 200, 200, 100);
      final strips = ScrimHolePainter.scrimStrips(screen, [hole]);

      expect(strips, hasLength(4));
      // Top/bottom span the whole screen width; left/right — the hole height.
      expect(strips, contains(const Rect.fromLTWH(0, 0, 800, 200)));
      expect(strips, contains(const Rect.fromLTWH(0, 300, 800, 300)));
      expect(strips, contains(const Rect.fromLTWH(0, 200, 300, 100)));
      expect(strips, contains(const Rect.fromLTWH(500, 200, 300, 100)));
      expectNoOverlaps(strips);
    });

    test('two side-by-side holes — strips between them, no overlaps', () {
      const a = Rect.fromLTWH(100, 100, 200, 80);
      const b = Rect.fromLTWH(500, 100, 200, 80);
      final strips = ScrimHolePainter.scrimStrips(screen, [a, b]);

      // top (0..100), between the holes (300..500 at 100..180), right,
      // bottom — plus the outer sides.
      expect(strips, contains(const Rect.fromLTWH(0, 0, 800, 100)));
      expect(strips, contains(const Rect.fromLTWH(300, 100, 200, 80)));
      expect(strips, contains(const Rect.fromLTWH(700, 100, 100, 80)));
      expect(strips, contains(const Rect.fromLTWH(0, 100, 100, 80)));
      expect(strips, contains(const Rect.fromLTWH(0, 180, 800, 420)));
      expectNoOverlaps(strips);
    });

    test('overlapping holes — the union refined into non-overlapping strips',
        () {
      // b is fully inside a: the union of holes is just a. The strip
      // decomposition may be finer (b's edges add bands) but must cover the
      // same area and never touch b (the hole area is scrim-free).
      const a = Rect.fromLTWH(100, 100, 300, 150);
      const b = Rect.fromLTWH(150, 120, 100, 80);
      final strips = ScrimHolePainter.scrimStrips(screen, [a, b]);

      double area(List<Rect> rs) =>
          rs.fold(0.0, (s, r) => s + r.width * r.height);
      expect(
        area(strips),
        area(ScrimHolePainter.scrimStrips(screen, [a])),
        reason: 'b is inside a — the scrim area is unchanged',
      );
      expectNoOverlaps(strips);
      for (final s in strips) {
        expect(s.overlaps(b), isFalse,
            reason: 'no strip covers the inner hole $s');
      }
    });

    test('a hole at the left edge — 3 strips (no left one)', () {
      const hole = Rect.fromLTWH(0, 200, 200, 100);
      final strips = ScrimHolePainter.scrimStrips(screen, [hole]);
      expect(strips, hasLength(3));
      expect(
        strips.every((r) => r.left >= 0),
        isTrue,
        reason: 'no strip is left of the screen',
      );
    });

    test('a hole partially above the screen — strips clamped, none degenerate',
        () {
      // The hole starts above the screen: hole.top = -50.
      const hole = Rect.fromLTWH(300, -50, 200, 400); // bottom = 350
      final strips = ScrimHolePainter.scrimStrips(screen, [hole]);
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

    test('a hole bigger than the screen — no scrim (nothing to darken)', () {
      const hole = Rect.fromLTWH(-100, -100, 1000, 800);
      final strips = ScrimHolePainter.scrimStrips(screen, [hole]);
      expect(strips, isEmpty);
    });

    test('a hole exactly the screen — no scrim', () {
      final strips = ScrimHolePainter.scrimStrips(screen, [screen]);
      expect(strips, isEmpty);
    });

    test('no holes — the whole screen is scrimmed', () {
      final strips = ScrimHolePainter.scrimStrips(screen, const []);
      expect(strips, [screen]);
    });

    test('a hole fully outside the screen — the whole screen is scrimmed', () {
      const offscreen = Rect.fromLTWH(-500, -500, 100, 100);
      final strips = ScrimHolePainter.scrimStrips(screen, [offscreen]);
      expect(strips, [screen]);
    });
  });

  group('ScrimHolePainter paint (no first-frame flash)', () {
    test('unpositioned in active mode — paints NOTHING', () {
      final canvas = TestRecordingCanvas();
      final painter = ScrimHolePainter(
        resolvers: const [UnpositionedHintResolver()],
        color: const Color(0x80000000),
      );
      painter.paint(canvas, const Size(800, 600));
      expect(canvas.invocations, isEmpty,
          reason: 'active mode draws nothing until the position is known — '
              'a full rect anchored at the target would flash a misaligned '
              'partial dim');
    });

    test('unpositioned in waiting mode (flag) — a full-scrim rect', () {
      final canvas = TestRecordingCanvas();
      final painter = ScrimHolePainter(
        resolvers: const [UnpositionedHintResolver()],
        color: const Color(0x80000000),
        paintFullScrimWhenUnpositioned: true,
      );
      painter.paint(canvas, const Size(800, 600));
      expect(canvas.invocations, hasLength(1));
      expect(canvas.invocations.single.invocation.memberName, #drawRect);
    });

    test('positioned — one drawRect per strip', () {
      final canvas = TestRecordingCanvas();
      final resolver = _FakeResolver(const PositionedHint(
        translation: Offset(100, 100),
        size: Size(200, 80),
      ));
      final painter = ScrimHolePainter(
        resolvers: [resolver],
        color: const Color(0x80000000),
      );
      painter.paint(canvas, const Size(800, 600));
      expect(
        canvas.invocations
            .where((r) => r.invocation.memberName == #drawRect)
            .length,
        4,
        reason: 'a centered hole → 4 strips',
      );
    });
  });

  group('ScrimHolePainter', () {
    test('shouldRepaint: only when the resolver set or color changes', () {
      final resolver = _FakeResolver(const PositionedHint(
        translation: Offset.zero,
        size: Size(10, 10),
      ));
      final a = ScrimHolePainter(
        resolvers: [resolver],
        color: const Color(0xFF000000),
      );
      final same = ScrimHolePainter(
        resolvers: [resolver],
        color: const Color(0xFF000000),
      );
      final otherColor = ScrimHolePainter(
        resolvers: [resolver],
        color: const Color(0x80000000),
      );
      final otherResolver = _FakeResolver(const UnpositionedHint());
      final other = ScrimHolePainter(
        resolvers: [otherResolver],
        color: const Color(0xFF000000),
      );

      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(otherColor), isTrue);
      expect(a.shouldRepaint(other), isTrue);
    });
  });
}
