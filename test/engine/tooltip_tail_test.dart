import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/tooltip_tail.dart';

void main() {
  group('tailSideFor', () {
    // hole 100..300 x, 200..280 y
    const hole = Rect.fromLTWH(100, 200, 200, 80);

    test('tooltip above → bottom side (the arrow points down at the hole)', () {
      const tip = Rect.fromLTWH(100, 40, 200, 100); // bottom = 140 < hole.top
      expect(tailSideFor(tip, hole), TailSide.bottom);
    });

    test('tooltip below → top side', () {
      const tip = Rect.fromLTWH(100, 300, 200, 100); // top = 300 > hole.bottom
      expect(tailSideFor(tip, hole), TailSide.top);
    });

    test('tooltip left → right side', () {
      const tip = Rect.fromLTWH(0, 200, 80, 100); // right = 80 < hole.left
      expect(tailSideFor(tip, hole), TailSide.right);
    });

    test('tooltip right → left side', () {
      const tip = Rect.fromLTWH(320, 200, 80, 100); // left = 320 > hole.right
      expect(tailSideFor(tip, hole), TailSide.left);
    });

    test('taller-than-the-hole side tooltip: the parallel axis is the tiebreak',
        () {
      // To the right AND extending below the hole: the separated axis (x)
      // decides — left side, not top/bottom.
      const tip = Rect.fromLTWH(320, 240, 80, 200);
      expect(tailSideFor(tip, hole), TailSide.left);
    });

    test('sub-pixel float noise does not lose the side', () {
      // The compositor transform carries float noise; a 0.25 px overlap must
      // still resolve to the side (the epsilon is 0.5).
      const tip = Rect.fromLTWH(100, 40, 200, 100.25);
      expect(tailSideFor(tip, hole), TailSide.bottom);
    });

    test('overlapping (degenerate fallback) → null, no tail', () {
      const tip = Rect.fromLTWH(100, 200, 200, 80); // exactly the hole
      expect(tailSideFor(tip, hole), isNull);
    });
  });

  group('tailPath', () {
    const tooltip = Rect.fromLTWH(100, 40, 200, 100);
    const hole = Rect.fromLTWH(190, 160, 20, 20); // hole center = (200, 170)
    const length = 10.0;
    const width = 14.0;

    test('bottom: base on the bottom edge, apex below, centered on the hole',
        () {
      final path = tailPath(
        side: TailSide.bottom,
        tooltipSize: const Size(200, 100),
        hole: hole,
        tooltip: tooltip,
        length: length,
        width: width,
      );
      final bounds = path.getBounds();
      // tooltip-local hole center x = 200 - 100 = 100 → the isosceles
      // triangle's bounding box is centered on it.
      expect(bounds.center.dx, closeTo(100, 0.01));
      expect(bounds.top, closeTo(100 - 0.5, 0.01)); // base on the bottom edge
      expect(bounds.bottom, closeTo(100 + length, 0.01)); // apex beyond it
      expect(bounds.width, closeTo(width, 0.01));
    });

    test('top: apex above the tooltip', () {
      final path = tailPath(
        side: TailSide.top,
        tooltipSize: const Size(200, 100),
        hole: hole,
        tooltip: tooltip,
        length: length,
        width: width,
      );
      final bounds = path.getBounds();
      expect(bounds.center.dx, closeTo(100, 0.01));
      expect(bounds.top, closeTo(-length, 0.01));
      expect(bounds.bottom, closeTo(0.5, 0.01));
    });

    test('left: apex to the left, centered on the hole vertically', () {
      // The hole's center must sit within the tooltip's vertical extent,
      // otherwise the clamp (tail base stays on the edge) pins the center.
      const sideHole = Rect.fromLTWH(190, 70, 20, 40); // center y = 90
      final path = tailPath(
        side: TailSide.left,
        tooltipSize: const Size(200, 100),
        hole: sideHole,
        tooltip: tooltip,
        length: length,
        width: width,
      );
      final bounds = path.getBounds();
      // tooltip-local hole center y = 90 - 40 = 50.
      expect(bounds.center.dy, closeTo(50, 0.01));
      expect(bounds.left, closeTo(-length, 0.01));
      expect(bounds.right, closeTo(0.5, 0.01));
      expect(bounds.height, closeTo(width, 0.01));
    });

    test('right: apex to the right', () {
      const sideHole = Rect.fromLTWH(190, 70, 20, 40); // center y = 90
      final path = tailPath(
        side: TailSide.right,
        tooltipSize: const Size(200, 100),
        hole: sideHole,
        tooltip: tooltip,
        length: length,
        width: width,
      );
      final bounds = path.getBounds();
      expect(bounds.center.dy, closeTo(50, 0.01));
      expect(bounds.left, closeTo(200 - 0.5, 0.01));
      expect(bounds.right, closeTo(200 + length, 0.01));
    });

    test('hole center off the tooltip edge: the base is clamped inside', () {
      // Hole center far to the right (x 900 in global): a base outside the
      // tooltip width would detach the tail — it clamps to the edge.
      const offTooltip = Rect.fromLTWH(890, 160, 20, 20);
      final path = tailPath(
        side: TailSide.bottom,
        tooltipSize: const Size(200, 100),
        hole: offTooltip,
        tooltip: tooltip,
        length: length,
        width: width,
      );
      final bounds = path.getBounds();
      expect(bounds.right, lessThanOrEqualTo(200));
    });

    test('degenerate tiny tooltip: a centered base instead of off-edge', () {
      // Tooltip edge (40) shorter than the base (14+14=28 is fine — use
      // width 60 > 40): the clamp falls back to the center.
      final path = tailPath(
        side: TailSide.bottom,
        tooltipSize: const Size(40, 40),
        hole: hole,
        tooltip: const Rect.fromLTWH(100, 40, 40, 40),
        length: length,
        width: 60,
      );
      final bounds = path.getBounds();
      expect(bounds.center.dx, closeTo(20, 0.01)); // 40/2
    });
  });

  group('TooltipTailPainter', () {
    test('shouldRepaint: hole/color changes repaint, same values do not', () {
      final key = GlobalKey();
      final a = TooltipTailPainter(
        positionKey: key,
        hole: const Rect.fromLTWH(0, 0, 10, 10),
        color: const Color(0xFF000000),
      );
      final same = TooltipTailPainter(
        positionKey: key,
        hole: const Rect.fromLTWH(0, 0, 10, 10),
        color: const Color(0xFF000000),
      );
      final moved = TooltipTailPainter(
        positionKey: key,
        hole: const Rect.fromLTWH(5, 0, 10, 10),
        color: const Color(0xFF000000),
      );
      final recolored = TooltipTailPainter(
        positionKey: key,
        hole: const Rect.fromLTWH(0, 0, 10, 10),
        color: const Color(0xFF111111),
      );
      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(moved), isTrue);
      expect(a.shouldRepaint(recolored), isTrue);
    });
  });
}
