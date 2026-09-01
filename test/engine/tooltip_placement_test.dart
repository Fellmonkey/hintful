import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/tooltip_placement.dart';
import 'package:hintful/engine/specs.dart';

void main() {
  const screen = Rect.fromLTWH(0, 0, 800, 600);

  group('explicit side', () {
    const hole = Rect.fromLTWH(100, 100, 200, 80); // right=300, bottom=180
    const tooltip = Size(160, 60);

    test('bottom: below the hole with a gap, centered', () {
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: hole,
        position: TooltipPosition.bottom,
      );
      // x: 100 + (200-160)/2 = 120; y: 180 + 12 = 192
      expect(
          d.getPositionForChild(screen.size, tooltip), const Offset(120, 192));
    });

    test('top: above the hole', () {
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: hole,
        position: TooltipPosition.top,
      );
      // y: 100 - 12 - 60 = 28
      expect(
          d.getPositionForChild(screen.size, tooltip), const Offset(120, 28));
    });

    test('right: to the right, vertically centered', () {
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: hole,
        position: TooltipPosition.right,
      );
      // x: 300 + 12 = 312; y: 100 + (80-60)/2 = 110
      expect(
          d.getPositionForChild(screen.size, tooltip), const Offset(312, 110));
    });

    test('left: to the left', () {
      const h = Rect.fromLTWH(300, 100, 200, 80);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.left,
      );
      // x: 300 - 12 - 160 = 128; y: 110
      expect(
          d.getPositionForChild(screen.size, tooltip), const Offset(128, 110));
    });
  });

  group('mirroring (auto-flip)', () {
    test('bottom does not fit at the bottom edge → top', () {
      const h = Rect.fromLTWH(100, 500, 200, 80); // bottom=580: 580+12+60>600
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      expect(
        d.getPositionForChild(screen.size, const Size(160, 60)),
        const Offset(120, 428), // 500 - 12 - 60
      );
    });

    test('top does not fit at the top edge → bottom', () {
      const h = Rect.fromLTWH(100, 0, 200, 80);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.top,
      );
      expect(
        d.getPositionForChild(screen.size, const Size(160, 60)),
        const Offset(120, 92), // 0 + 80 + 12
      );
    });

    test('left does not fit at the left edge → right', () {
      const h = Rect.fromLTWH(0, 100, 200, 80);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.left,
      );
      expect(
        d.getPositionForChild(screen.size, const Size(160, 60)),
        const Offset(212, 110), // right: x = 200 + 12
      );
    });
  });

  group('auto', () {
    test('the side with the most free space', () {
      // Space: bottom 50, top 500, right 700, left 0 → right first.
      const h = Rect.fromLTWH(0, 500, 100, 50);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.auto,
      );
      expect(
        d.getPositionForChild(screen.size, const Size(80, 120)),
        const Offset(112, 465), // x = 100+12; y = 500 + (50-120)/2
      );
    });

    test('with equal pairs, the side with really more space wins', () {
      // The hole is centered, but the screen is 800x600: horizontal space
      // (350) beats vertical (250) → right.
      const h = Rect.fromLTWH(350, 250, 100, 100);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.auto,
      );
      expect(
        d.getPositionForChild(screen.size, const Size(100, 60)),
        const Offset(462, 270), // x = 450 + 12; y = 250 + (100-60)/2
      );
    });
  });

  group('edge cases', () {
    test('tooltip bigger than the screen → a screen corner with a margin', () {
      const h = Rect.fromLTWH(100, 100, 200, 80);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      expect(
        d.getPositionForChild(screen.size, const Size(900, 700)),
        const Offset(8, 8),
      );
    });

    test('wide tooltip: centering clamped on-screen (does not overflow)', () {
      const h = Rect.fromLTWH(700, 100, 100, 80); // the hole at the right edge
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      final offset = d.getPositionForChild(screen.size, const Size(400, 60));
      // x: 700 + (100-400)/2 = 550 → clamped to [0, 800-400=400] → 400;
      // the right edge exactly at the screen boundary — legitimate.
      expect(offset.dx, 400);
    });

    test(
        'gap: the offset from the hole is exactly gap, the hole is not '
        'covered', () {
      const h = Rect.fromLTWH(100, 100, 200, 80);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
        gap: 24,
      );
      final offset = d.getPositionForChild(screen.size, const Size(160, 60));
      expect(offset.dy - h.bottom, 24);
      // Bottom side: the tooltip is entirely below the hole — no overlap.
      final rect = offset & const Size(160, 60);
      expect(rect.overlaps(h), isFalse);
    });

    test('hole bigger than the screen: no crash, a screen corner', () {
      const h = Rect.fromLTWH(0, 0, 2000, 1000); // the target > the screen
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.auto,
      );
      final offset = d.getPositionForChild(screen.size, const Size(160, 60));
      expect(offset, const Offset(8, 8));
    });
  });

  group('safe area (keep-in-safe-area)', () {
    test('bottom blocked by the home indicator → mirrored to top', () {
      // hole bottom = 440; tooltip 100 tall: bottom = 440+12+100 = 552,
      // fits the screen (600) but not the safe rect (bottom 540) → top.
      const h = Rect.fromLTWH(100, 380, 200, 60);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
        safeArea: const EdgeInsets.only(bottom: 60),
      );
      // top: y = 380 - 12 - 100 = 268; x centered = 100 + (200-160)/2 = 120
      expect(
        d.getPositionForChild(screen.size, const Size(160, 100)),
        const Offset(120, 268),
      );
    });

    test('without the inset the same geometry stays bottom (control)', () {
      // The identical tooltip fits the bare screen → bottom, not top.
      const h = Rect.fromLTWH(100, 380, 200, 60);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      expect(
        d.getPositionForChild(screen.size, const Size(160, 100)),
        const Offset(120, 452), // 440 + 12
      );
    });

    test('auto free-space counts the safe rect, not the bare screen', () {
      // A wide hole near the top: the screen free space — bottom 440 beats
      // top 100 and the sides (50 each) → bottom. With a 350 bottom inset
      // the bottom shrinks to 250-160=90 → top (100) wins.
      const h = Rect.fromLTWH(50, 100, 700, 60); // x 50..750, y 100..160
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.auto,
        safeArea: const EdgeInsets.only(bottom: 350),
      );
      // top: y = 100 - 12 - 60 = 28; x centered = 50 + (700-160)/2 = 320
      expect(
        d.getPositionForChild(screen.size, const Size(160, 60)),
        const Offset(320, 28),
      );
    });

    test('without the inset the same hole goes bottom (control)', () {
      const h = Rect.fromLTWH(50, 100, 700, 60);
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.auto,
      );
      expect(
        d.getPositionForChild(screen.size, const Size(160, 60)),
        const Offset(320, 172), // y: 160 + 12
      );
    });

    test('centering clamps into the safe rect (side inset)', () {
      const h = Rect.fromLTWH(700, 100, 100, 80); // the hole at the right edge
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
        safeArea: const EdgeInsets.only(right: 100),
      );
      final offset = d.getPositionForChild(screen.size, const Size(400, 60));
      // x: 550 → clamped to [0, (800-100)-400=300] → 300 — inside the inset.
      expect(offset.dx, 300);
      expect(offset.dx + 400, lessThanOrEqualTo(800 - 100));
    });
  });

  group('extraHoles (multi-target: not covering other spotlighted targets)',
      () {
    const hole = Rect.fromLTWH(100, 100, 200, 80); // right=300, bottom=180
    const tooltip = Size(160, 60);

    test('bottom rejected when an extra hole sits below → mirrored to top', () {
      const extra = Rect.fromLTWH(120, 200, 160, 60); // y 200..260
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: hole,
        position: TooltipPosition.bottom,
        extraHoles: const [extra],
      );
      // bottom would be 192..252 — overlapping the extra → top.
      expect(
        d.getPositionForChild(screen.size, tooltip),
        const Offset(120, 28), // y: 100 - 12 - 60
      );
    });

    test('without the extra hole the same geometry stays bottom (control)', () {
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: hole,
        position: TooltipPosition.bottom,
      );
      expect(
        d.getPositionForChild(screen.size, tooltip),
        const Offset(120, 192), // y: 180 + 12
      );
    });

    test('right rejected when an extra hole sits to the right → next side', () {
      const extra = Rect.fromLTWH(320, 100, 200, 80); // x 320..520
      final d = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: hole,
        position: TooltipPosition.right,
        extraHoles: const [extra],
      );
      // right (312..472) overlaps the extra; left is off-screen; bottom fits.
      expect(
        d.getPositionForChild(screen.size, tooltip),
        const Offset(120, 192),
      );
    });
  });

  group('placeTooltip (pure core, multi-content collisions)', () {
    const hole = Rect.fromLTWH(350, 250, 100, 100); // right=450, bottom=350
    const size = Size(160, 60);

    test('a second slot avoids an already-placed tooltip on the same side', () {
      final primary = placeTooltip(
        screen: screen,
        hole: hole,
        position: TooltipPosition.bottom,
        size: size,
        safeArea: EdgeInsets.zero,
        avoid: const [hole],
      );
      final primaryRect = primary & size;
      expect(primaryRect.top, hole.bottom + 12);

      // The extra also wants the bottom side — blocked by the primary's rect
      // → the next side in the order (top).
      final extra = placeTooltip(
        screen: screen,
        hole: hole,
        position: TooltipPosition.bottom,
        size: size,
        safeArea: EdgeInsets.zero,
        avoid: [hole, primaryRect],
      );
      final extraRect = extra & size;
      expect(extraRect.overlaps(primaryRect), isFalse);
      expect(extraRect.bottom, lessThan(hole.top),
          reason: 'mirrored above the hole');
    });

    test(
        'the corner fallback prefers a free corner over the blocked '
        'top-left', () {
      // A placed tooltip occupies the top-left quadrant; no side of the
      // hole fits the extra (600x250) — the bottom-left corner is free and
      // wins over the (blocked) top-left.
      const topLeftBlock = Rect.fromLTWH(0, 0, 400, 300);
      const tallHole = Rect.fromLTWH(400, 150, 100, 100); // 150..250
      final offset = placeTooltip(
        screen: screen,
        hole: tallHole,
        position: TooltipPosition.bottom,
        size: const Size(600, 250),
        safeArea: EdgeInsets.zero,
        avoid: [tallHole, topLeftBlock],
      );
      expect(offset, const Offset(8, 342));
    });
  });

  group('TooltipMultiPlacementDelegate (two slots on the same side)', () {
    testWidgets('the extra is mirrored away — the slots do not overlap',
        (tester) async {
      const hole = Rect.fromLTWH(350, 250, 100, 100);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: CustomMultiChildLayout(
              delegate: TooltipMultiPlacementDelegate(
                screenLocal: screen,
                holeLocal: hole,
                primaryPosition: TooltipPosition.bottom,
                extraPositions: const [TooltipPosition.bottom],
              ),
              children: [
                LayoutId(
                  id: TooltipMultiPlacementDelegate.primaryId,
                  child: Container(
                    width: 160,
                    height: 60,
                    color: Colors.red,
                  ),
                ),
                LayoutId(
                  id: TooltipMultiPlacementDelegate.extraId(0),
                  child: Container(
                    width: 160,
                    height: 60,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final red = find
          .byWidgetPredicate((w) => w is Container && w.color == Colors.red);
      final blue = find
          .byWidgetPredicate((w) => w is Container && w.color == Colors.blue);
      final primaryRect = tester.getRect(red);
      final extraRect = tester.getRect(blue);

      expect(primaryRect.top, hole.bottom + 12);
      expect(extraRect.overlaps(primaryRect), isFalse);
      expect(extraRect.bottom, lessThan(hole.top),
          reason: 'same preferred side → the extra mirrored above');
    });
  });

  group('shouldRelayout', () {
    const h = Rect.fromLTWH(100, 100, 200, 80);

    test('equal values — false (no relayout on every build)', () {
      final a = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      final same = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      expect(a.shouldRelayout(same), isFalse);
    });

    test('a changed side/hole/screen — true', () {
      final a = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      final otherSide = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.top,
      );
      final moved = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h.shift(const Offset(10, 0)),
        position: TooltipPosition.bottom,
      );
      final movedScreen = TooltipPlacementDelegate(
        screenLocal: const Rect.fromLTWH(-5, 0, 800, 600),
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      expect(a.shouldRelayout(otherSide), isTrue);
      expect(a.shouldRelayout(moved), isTrue);
      expect(a.shouldRelayout(movedScreen), isTrue);
    });

    test('a changed safeArea — true', () {
      final a = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      final inset = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
        safeArea: const EdgeInsets.all(10),
      );
      expect(a.shouldRelayout(inset), isTrue);
    });

    test('extraHoles: a changed list — true, an equal list — false', () {
      final withExtra = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
        extraHoles: const [Rect.fromLTWH(0, 0, 10, 10)],
      );
      final without = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
      );
      final same = TooltipPlacementDelegate(
        screenLocal: screen,
        holeLocal: h,
        position: TooltipPosition.bottom,
        extraHoles: const [Rect.fromLTWH(0, 0, 10, 10)],
      );
      expect(without.shouldRelayout(withExtra), isTrue);
      expect(withExtra.shouldRelayout(same), isFalse);
    });
  });
}
