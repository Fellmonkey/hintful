import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/pulse_painter.dart';
import 'package:hintful/engine/position_resolver.dart';

class _FakeResolver implements HintPositionResolver {
  _FakeResolver(this.position);

  final HintPosition position;

  @override
  HintPosition resolve() => position;
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

  group('PulsePainter', () {
    test('shouldRepaint: only when animation/resolver/color change', () {
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
      final otherResolver = _FakeResolver(const UnpositionedHint());
      final other = PulsePainter(
        animation: controller,
        resolver: otherResolver,
        color: const Color(0xFFFFFFFF),
      );

      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(otherColor), isTrue);
      expect(a.shouldRepaint(other), isTrue);
    });
  });
}
