import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/src/engine/overlay/pulse_painter.dart';
import 'package:hintful/src/engine/position_resolver.dart';
import 'package:hintful/src/engine/specs.dart' show FocusShape;

class _FakeResolver implements HintPositionResolver {
  _FakeResolver(this.position);

  final PositionedHint? position;

  @override
  PositionedHint? resolve() => position;
}

void main() {
  group('pulseRing (pure geometry)', () {
    const size = Size(120, 60);

    test('phase 0 — the ring equals the hole', () {
      final (ring, opacity) = PulsePainter.pulseRing(0, size);
      expect(ring, const Rect.fromLTWH(0, 0, 120, 60));
      expect(opacity, 1.0);
    });

    test('the ring inflates by phase * expansion in every direction', () {
      final (ring, _) = PulsePainter.pulseRing(0.5, size);
      // half of 24 → 12 on each side.
      expect(ring, const Rect.fromLTWH(-12, -12, 144, 84));
    });

    test('opacity holds for the first half, fades to zero by the end', () {
      expect(PulsePainter.pulseRing(0.25, size).$2, 1.0);
      expect(PulsePainter.pulseRing(0.75, size).$2, 0.5);
      expect(PulsePainter.pulseRing(1.0, size).$2, 0.0);
    });

    test('a phase outside 0..1 is clamped, never negative opacity', () {
      final (ring, opacity) = PulsePainter.pulseRing(1.5, size);
      expect(ring, const Rect.fromLTWH(-24, -24, 168, 108));
      expect(opacity, 0.0);
    });
  });

  group('PulsePainter focusShape (the ring strokes the scrim holeShape)', () {
    Path paintedPath(TestRecordingCanvas canvas) {
      final drawPath = canvas.invocations
          .where((i) => i.invocation.memberName == #drawPath)
          .toList();
      expect(drawPath, hasLength(1),
          reason: 'exactly one stroked path per paint');
      return drawPath.single.invocation.positionalArguments.first as Path;
    }

    test('rect — the plain rect path', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(
          translation: Offset(50, 50), size: Size(80, 40)));
      final p = PulsePainter(
          animation: null,
          resolver: r,
          color: const Color(0xFFFFFFFF),
          focusShape: FocusShape.rectangle,
          focusPadding: 4);
      p.paint(canvas, const Size(800, 600));
      // hole = (46,46,88,48) — no corner rounding on the plain rect.
      expect(
          paintedPath(canvas).getBounds(), const Rect.fromLTWH(46, 46, 88, 48));
    });

    test('circle — the longer side becomes the diameter', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(
          translation: Offset(50, 50), size: Size(80, 40)));
      final p = PulsePainter(
          animation: null,
          resolver: r,
          color: const Color(0xFFFFFFFF),
          focusShape: FocusShape.circle,
          focusPadding: 0);
      p.paint(canvas, const Size(800, 600));
      // side = max(80, 40) = 80 around the hole's center (90, 70).
      expect(
          paintedPath(canvas).getBounds(), const Rect.fromLTWH(50, 30, 80, 80));
    });

    test('rounded — the clamped-corner rect path', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(
          translation: Offset(50, 50), size: Size(80, 40)));
      final p = PulsePainter(
          animation: null,
          resolver: r,
          color: const Color(0xFFFFFFFF),
          focusShape: FocusShape.roundedRect,
          focusPadding: 4);
      p.paint(canvas, const Size(800, 600));
      expect(
          paintedPath(canvas).getBounds(), const Rect.fromLTWH(46, 46, 88, 48));
    });

    test(
        'the painted ring is the pure pulseRing geometry, shifted to the '
        'hole', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(
          translation: Offset(50, 50), size: Size(80, 40)));
      final controller = AnimationController.unbounded(vsync: const TestVSync())
        ..value = 0.5;
      addTearDown(controller.dispose);
      final p = PulsePainter(
        animation: controller,
        resolver: r,
        color: const Color(0xFFFFFFFF),
        focusShape: FocusShape.rectangle,
        focusPadding: 4,
      );
      p.paint(canvas, const Size(800, 600));

      // hole = (46, 46, 88, 48); phase 0.5 inflates it by 12 on every side.
      expect(paintedPath(canvas).getBounds(),
          const Rect.fromLTWH(34, 34, 112, 72));
    });
  });

  group('PulsePainter', () {
    test(
        'shouldRepaint: on animation/resolver/color/shape/padding change, '
        'not otherwise', () {
      final resolver = _FakeResolver(
          const PositionedHint(translation: Offset.zero, size: Size(10, 10)));
      final controller =
          AnimationController.unbounded(vsync: const TestVSync());
      addTearDown(controller.dispose);

      final a = PulsePainter(
        animation: controller,
        resolver: resolver,
        color: const Color(0xFFFFFFFF),
      );
      final same = PulsePainter(
        animation: controller,
        resolver: resolver,
        color: const Color(0xFFFFFFFF),
      );
      final otherColor = PulsePainter(
        animation: controller,
        resolver: resolver,
        color: const Color(0xFFFF0000),
      );
      final otherResolver = _FakeResolver(null);
      final other = PulsePainter(
        animation: controller,
        resolver: otherResolver,
        color: const Color(0xFFFFFFFF),
      );
      final otherShape = PulsePainter(
        animation: controller,
        resolver: resolver,
        color: const Color(0xFFFFFFFF),
        focusShape: FocusShape.circle,
      );
      final otherPadding = PulsePainter(
        animation: controller,
        resolver: resolver,
        color: const Color(0xFFFFFFFF),
        focusPadding: 12,
      );

      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(otherColor), isTrue);
      expect(a.shouldRepaint(other), isTrue);
      // A step change must re-aim the ring: shape/padding move with the step.
      expect(a.shouldRepaint(otherShape), isTrue);
      expect(a.shouldRepaint(otherPadding), isTrue);
    });
  });
}
