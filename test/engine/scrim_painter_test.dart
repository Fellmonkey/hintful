import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/engine/position_resolver.dart';
import 'package:hintful/engine/specs.dart' show FocusShape;

/// Fake resolver: a deterministic position (or Unpositioned).
class _FakeResolver implements HintPositionResolver {
  _FakeResolver(this.position);

  final HintPosition position;

  @override
  HintPosition resolve() => position;
}

void main() {
  /// Recorded paint ops that punch holes: any canvas draw whose paint
  /// clears (BlendMode.clear), regardless of the shape call.
  Iterable<RecordedInvocation> holeOps(TestRecordingCanvas canvas) =>
      canvas.invocations.where((record) {
        final args = record.invocation.positionalArguments;
        return args.length > 1 &&
            args[1] is Paint &&
            (args[1] as Paint).blendMode == BlendMode.clear;
      });

  /// Recorded dim rects: drawRect ops with a normal (non-clear) paint.
  Iterable<RecordedInvocation> dimRects(TestRecordingCanvas canvas) =>
      canvas.invocations.where((record) =>
          record.invocation.memberName == #drawRect &&
          (record.invocation.positionalArguments[1] as Paint).blendMode !=
              BlendMode.clear);

  group('ScrimHolePainter paint (no first-frame flash)', () {
    test('dim + punch run inside an isolated layer', () {
      // BlendMode.clear without saveLayer would erase the app painted
      // beneath this picture (white box instead of the target). The layer
      // confines the punch to the dim.
      final canvas = TestRecordingCanvas();
      final resolver = _FakeResolver(const PositionedHint(
        translation: Offset(100, 100),
        size: Size(200, 80),
      ));
      ScrimHolePainter(
        resolvers: [resolver],
        color: const Color(0x80000000),
      ).paint(canvas, const Size(800, 600));
      final ops = canvas.invocations
          .map((r) => r.invocation.memberName)
          .toList();
      expect(ops.first, #saveLayer);
      expect(ops.last, #restore);
      expect(ops.where((m) => m == #drawRect).length, 1,
          reason: 'the dim rect');
      expect(ops.where((m) => m == #drawPath).length, 1,
          reason: 'the punched hole path');
    });

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
      expect(dimRects(canvas), hasLength(1));
      expect(holeOps(canvas), isEmpty);
    });
    test('positioned — one dim rect + one clear hole', () {
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
      // The full-screen dim (follower-local coords: shifted by -translation).
      final dims = dimRects(canvas).toList();
      expect(dims, hasLength(1));
      expect(
        dims.single.invocation.positionalArguments[0],
        const Rect.fromLTWH(-100, -100, 800, 600),
      );
      // One punched hole: the target rect + default padding.
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(-4, -4, 208, 88),
      );
    });
  });

  group('ScrimHolePainter.holeShape (one place for every hole)', () {
    test('rectangle — exact bounds', () {
      const hole = Rect.fromLTWH(10, 20, 80, 40);
      final shape = ScrimHolePainter.holeShape(hole, FocusShape.rectangle)!;
      expect(shape.getBounds(), hole);
    });

    test('circle — oval inscribed by the longest side', () {
      const hole = Rect.fromLTWH(10, 20, 80, 40);
      final shape = ScrimHolePainter.holeShape(hole, FocusShape.circle)!;
      expect(shape.getBounds(), const Rect.fromLTWH(10, 0, 80, 80));
    });

    test('rounded — RRect with radius 12', () {
      const hole = Rect.fromLTWH(10, 20, 80, 40);
      final shape = ScrimHolePainter.holeShape(hole, FocusShape.roundedRect)!;
      expect(shape.getBounds(), hole);
      // Corner pixel outside the R12 arc, inside the rect.
      expect(shape.contains(const Offset(11, 21)), isFalse);
      expect(shape.contains(const Offset(50, 40)), isTrue);
    });

    test('tiny hole — radius clamped to half the shortest side', () {
      const hole = Rect.fromLTWH(0, 0, 20, 20);
      final shape = ScrimHolePainter.holeShape(hole, FocusShape.roundedRect)!;
      // With the clamp (r = 10) the (3, 3) corner is inside the pill;
      // with an unclamped r = 12 arc it would fall outside.
      expect(shape.contains(const Offset(3, 3)), isTrue);
      expect(shape.contains(const Offset(0.5, 0.5)), isFalse);
      expect(shape.contains(const Offset(10, 10)), isTrue);
    });

    test('empty hole — null (cuts nothing)', () {
      expect(ScrimHolePainter.holeShape(Rect.zero, FocusShape.rectangle), isNull);
      expect(
        ScrimHolePainter.holeShape(
          const Rect.fromLTWH(0, 0, 100, 50).inflate(-100), FocusShape.roundedRect,
        ),
        isNull,
      );
    });
  });

  group('ScrimHolePainter focusShape', () {
    test('rect (default) — sharp clear hole path', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(translation: Offset(100, 100), size: Size(80, 40)));
      final p = ScrimHolePainter(resolvers: [r], color: const Color(0x80000000), focusShape: FocusShape.rectangle, focusPadding: 4);
      p.paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(-4, -4, 88, 48),
      );
    });

    test('circle — one clear oval path', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(translation: Offset(100, 100), size: Size(80, 40)));
      final p = ScrimHolePainter(resolvers: [r], color: const Color(0x80000000), focusShape: FocusShape.circle, focusPadding: 0);
      p.paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      // Ø = the longest side (80), centered on the hole.
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(0, -20, 80, 80),
      );
    });

    test('rounded — one clear RRect path', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(translation: Offset(100, 100), size: Size(80, 40)));
      final p = ScrimHolePainter(resolvers: [r], color: const Color(0x80000000), focusShape: FocusShape.roundedRect, focusPadding: 4);
      p.paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(-4, -4, 88, 48),
      );
    });

    test('negative padding shrinks hole', () {
      final r = _FakeResolver(const PositionedHint(translation: Offset(0, 0), size: Size(100, 50)));
      final plain = ScrimHolePainter(resolvers: [r], color: const Color(0x80000000), focusShape: FocusShape.rectangle, focusPadding: 4);
      final shrink = ScrimHolePainter(resolvers: [r], color: const Color(0x80000000), focusShape: FocusShape.rectangle, focusPadding: -8);
      expect(plain.shouldRepaint(shrink), isTrue);
    });

    test('over-shrunk hole (inverted rect) paints full dim, no throw', () {
      // Negative padding beyond the target size inverts the hole rect.
      // Every shape degrades to a full dim (no hole punched), never throws.
      final r = _FakeResolver(const PositionedHint(translation: Offset(0, 0), size: Size(100, 50)));
      for (final shape in FocusShape.values) {
        final canvas = TestRecordingCanvas();
        final p = ScrimHolePainter(resolvers: [r], color: const Color(0x80000000), focusShape: shape, focusPadding: -100);
        p.paint(canvas, const Size(800, 600));
        expect(dimRects(canvas), hasLength(1), reason: 'shape $shape');
        expect(holeOps(canvas), isEmpty, reason: 'shape $shape: no hole cut');
      }
    });

    test('tiny hole: corner radius clamped, no throw', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(translation: Offset(0, 0), size: Size(20, 20)));
      final p = ScrimHolePainter(resolvers: [r], color: const Color(0x80000000), focusShape: FocusShape.roundedRect, focusPadding: 0);
      p.paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(0, 0, 20, 20),
      );
    });

    test('window size 800x600 — hole punched in follower-local coords', () {
      final canvas = TestRecordingCanvas();
      final r = _FakeResolver(const PositionedHint(translation: Offset(200, 150), size: Size(120, 80)));
      final p = ScrimHolePainter(resolvers: [r], color: const Color(0x80000000), focusShape: FocusShape.roundedRect, focusPadding: 4);
      p.paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      // Follower-local: the (128, 88) hole sits at the canvas origin.
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(-4, -4, 128, 88),
      );
    });
  });

  group('RectScrimPainter (explicit screen-space holes)', () {
    test('dim + punch run inside an isolated layer', () {
      final canvas = TestRecordingCanvas();
      RectScrimPainter(
        holes: const [Rect.fromLTWH(100, 300, 120, 40)],
        color: const Color(0x80000000),
      ).paint(canvas, const Size(800, 600));
      final ops = canvas.invocations
          .map((r) => r.invocation.memberName)
          .toList();
      expect(ops.first, #saveLayer);
      expect(ops.last, #restore);
    });

    RectScrimPainter painter({
      List<Rect> holes = const [Rect.fromLTWH(100, 300, 120, 40)],
      FocusShape focusShape = FocusShape.rectangle,
    }) =>
        RectScrimPainter(
          holes: holes,
          color: const Color(0x80000000),
          focusShape: focusShape,
        );

    test('dims fullscreen, then punches the hole with clear', () {
      final canvas = TestRecordingCanvas();
      painter().paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(100, 300, 120, 40),
      );
    });

    test('shaped variants punch shaped holes', () {
      for (final shape in [FocusShape.circle, FocusShape.roundedRect]) {
        final canvas = TestRecordingCanvas();
        painter(
          holes: const [Rect.fromLTWH(100, 100, 120, 80)],
          focusShape: shape,
        ).paint(canvas, const Size(800, 600));
        expect(dimRects(canvas), hasLength(1));
        final holes = holeOps(canvas).toList();
        expect(holes, hasLength(1));
        expect(holes.single.invocation.memberName, #drawPath);
      }
    });

    test('empty holes paint a full dim, no throw', () {
      for (final holes in [
        <Rect>[],
        [Rect.zero],
      ]) {
        final canvas = TestRecordingCanvas();
        painter(holes: holes).paint(canvas, const Size(800, 600));
        expect(dimRects(canvas), hasLength(1));
        expect(holeOps(canvas), isEmpty);
      }
    });

    test('outside holes are harmless (clipped by the canvas), no throw', () {
      for (final holes in [
        [const Rect.fromLTWH(-200, -200, 50, 50)],
        [const Rect.fromLTWH(900, 700, 50, 50)],
      ]) {
        final canvas = TestRecordingCanvas();
        painter(holes: holes).paint(canvas, const Size(800, 600));
        expect(dimRects(canvas), hasLength(1));
      }
    });

    test('shouldRepaint on color/shape/holes change', () {
      final a = painter();
      expect(a.shouldRepaint(painter()), isFalse);
      expect(
        a.shouldRepaint(
          painter(holes: const [Rect.fromLTWH(0, 0, 10, 10)]),
        ),
        isTrue,
      );
      expect(a.shouldRepaint(painter(focusShape: FocusShape.roundedRect)), isTrue);
    });
  });

  group('scrimClipPath (even-odd clip for the blur scrim)', () {
    const screen = Rect.fromLTWH(0, 0, 800, 600);

    test('cuts every shape without boolean ops', () {
      for (final shape in FocusShape.values) {
        final path = ScrimHolePainter.scrimClipPath(
          screen,
          const [Rect.fromLTWH(100, 100, 120, 80)],
          shape,
        );
        expect(path.fillType, PathFillType.evenOdd);
        expect(path.contains(const Offset(160, 140)), isFalse,
            reason: 'shape $shape: hole center is cut out');
        expect(path.contains(const Offset(10, 10)), isTrue,
            reason: 'shape $shape: far corner stays clipped in');
      }
    });

    test('empty holes clip to the full screen, no throw', () {
      final path = ScrimHolePainter.scrimClipPath(
        screen,
        const [],
        FocusShape.roundedRect,
      );
      expect(path.contains(const Offset(400, 300)), isTrue);
      expect(path.contains(const Offset(10, 10)), isTrue);
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



