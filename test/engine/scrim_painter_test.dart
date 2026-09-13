import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/src/engine/overlay/scrim_painter.dart';
import 'package:hintful/src/engine/specs.dart' show FocusShape;

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

  group('RectScrimPainter paint', () {
    test('dim + punch run inside an isolated layer', () {
      // BlendMode.clear without saveLayer would erase the app painted
      // beneath this picture (white box instead of the target). The layer
      // confines the punch to the dim.
      final canvas = TestRecordingCanvas();
      RectScrimPainter(
        holes: const [Rect.fromLTWH(100, 100, 200, 80)],
        color: const Color(0x80000000),
      ).paint(canvas, const Size(800, 600));
      final ops =
          canvas.invocations.map((r) => r.invocation.memberName).toList();
      expect(ops.first, #saveLayer);
      expect(ops.last, #restore);
      expect(ops.where((m) => m == #drawRect).length, 1,
          reason: 'the dim rect');
      expect(ops.where((m) => m == #drawPath).length, 1,
          reason: 'the punched hole path');
    });

    test('positioned — one dim rect + one clear hole', () {
      final canvas = TestRecordingCanvas();
      final painter = RectScrimPainter(
        holes: const [Rect.fromLTWH(100, 100, 200, 80)],
        color: const Color(0x80000000),
      );
      painter.paint(canvas, const Size(800, 600));
      final dims = dimRects(canvas).toList();
      expect(dims, hasLength(1));
      expect(
        dims.single.invocation.positionalArguments[0],
        const Rect.fromLTWH(0, 0, 800, 600),
      );
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(100, 100, 200, 80),
      );
    });
  });

  group('RectScrimPainter.holeShape (one place for every hole)', () {
    test('rectangle — exact bounds', () {
      const hole = Rect.fromLTWH(10, 20, 80, 40);
      final shape = RectScrimPainter.holeShape(hole, FocusShape.rectangle)!;
      expect(shape.getBounds(), hole);
    });

    test('circle — oval inscribed by the longest side', () {
      const hole = Rect.fromLTWH(10, 20, 80, 40);
      final shape = RectScrimPainter.holeShape(hole, FocusShape.circle)!;
      expect(shape.getBounds(), const Rect.fromLTWH(10, 0, 80, 80));
    });

    test('rounded — RRect with radius 12', () {
      const hole = Rect.fromLTWH(10, 20, 80, 40);
      final shape = RectScrimPainter.holeShape(hole, FocusShape.roundedRect)!;
      expect(shape.getBounds(), hole);
      // Corner pixel outside the R12 arc, inside the rect.
      expect(shape.contains(const Offset(11, 21)), isFalse);
      expect(shape.contains(const Offset(50, 40)), isTrue);
    });

    test('tiny hole — radius clamped to half the shortest side', () {
      const hole = Rect.fromLTWH(0, 0, 20, 20);
      final shape = RectScrimPainter.holeShape(hole, FocusShape.roundedRect)!;
      // With the clamp (r = 10) the (3, 3) corner is inside the pill;
      // with an unclamped r = 12 arc it would fall outside.
      expect(shape.contains(const Offset(3, 3)), isTrue);
      expect(shape.contains(const Offset(0.5, 0.5)), isFalse);
      expect(shape.contains(const Offset(10, 10)), isTrue);
    });

    test('empty hole — null (cuts nothing)', () {
      expect(
          RectScrimPainter.holeShape(Rect.zero, FocusShape.rectangle), isNull);
      expect(
        RectScrimPainter.holeShape(
          const Rect.fromLTWH(0, 0, 100, 50).inflate(-100),
          FocusShape.roundedRect,
        ),
        isNull,
      );
    });
  });

  group('RectScrimPainter focusShape', () {
    test('rect (default) — sharp clear hole path', () {
      final canvas = TestRecordingCanvas();
      final p = RectScrimPainter(
        holes: const [Rect.fromLTWH(100, 100, 88, 48)],
        color: const Color(0x80000000),
        focusShape: FocusShape.rectangle,
      );
      p.paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(100, 100, 88, 48),
      );
    });

    test('circle — one clear oval path', () {
      final canvas = TestRecordingCanvas();
      final p = RectScrimPainter(
        holes: const [Rect.fromLTWH(100, 100, 80, 40)],
        color: const Color(0x80000000),
        focusShape: FocusShape.circle,
      );
      p.paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      // Ø = the longest side (80), centered on the hole.
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(100, 80, 80, 80),
      );
    });

    test('rounded — one clear RRect path', () {
      final canvas = TestRecordingCanvas();
      final p = RectScrimPainter(
        holes: const [Rect.fromLTWH(100, 100, 88, 48)],
        color: const Color(0x80000000),
        focusShape: FocusShape.roundedRect,
      );
      p.paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      final holes = holeOps(canvas).toList();
      expect(holes, hasLength(1));
      expect(holes.single.invocation.memberName, #drawPath);
      expect(
        (holes.single.invocation.positionalArguments[0] as Path).getBounds(),
        const Rect.fromLTWH(100, 100, 88, 48),
      );
    });

    test('over-shrunk hole (inverted rect) paints full dim, no throw', () {
      // An inverted hole rect cuts nothing — every shape degrades to a full
      // dim (no hole punched), never throws.
      for (final shape in FocusShape.values) {
        final canvas = TestRecordingCanvas();
        final p = RectScrimPainter(
          holes: [const Rect.fromLTWH(0, 0, 100, 50).inflate(-100)],
          color: const Color(0x80000000),
          focusShape: shape,
        );
        p.paint(canvas, const Size(800, 600));
        expect(dimRects(canvas), hasLength(1), reason: 'shape $shape');
        expect(holeOps(canvas), isEmpty, reason: 'shape $shape: no hole cut');
      }
    });

    test('tiny hole: corner radius clamped, no throw', () {
      final canvas = TestRecordingCanvas();
      final p = RectScrimPainter(
        holes: const [Rect.fromLTWH(0, 0, 20, 20)],
        color: const Color(0x80000000),
        focusShape: FocusShape.roundedRect,
      );
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
  });

  group('RectScrimPainter waiting mode (empty holes)', () {
    test('dims fullscreen, no punch', () {
      final canvas = TestRecordingCanvas();
      RectScrimPainter(
        holes: const [],
        color: const Color(0x80000000),
      ).paint(canvas, const Size(800, 600));
      expect(dimRects(canvas), hasLength(1));
      expect(holeOps(canvas), isEmpty);
    });
  });

  group('scrimClipPath (even-odd clip for the blur scrim)', () {
    const screen = Rect.fromLTWH(0, 0, 800, 600);

    test('cuts every shape without boolean ops', () {
      for (final shape in FocusShape.values) {
        final path = RectScrimPainter.scrimClipPath(
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
      final path = RectScrimPainter.scrimClipPath(
        screen,
        const [],
        FocusShape.roundedRect,
      );
      expect(path.contains(const Offset(400, 300)), isTrue);
      expect(path.contains(const Offset(10, 10)), isTrue);
    });
  });

  group('RectScrimPainter.shouldRepaint', () {
    RectScrimPainter painter({
      List<Rect> holes = const [Rect.fromLTWH(100, 300, 120, 40)],
      FocusShape focusShape = FocusShape.rectangle,
      Color color = const Color(0xFF000000),
    }) =>
        RectScrimPainter(holes: holes, color: color, focusShape: focusShape);

    test('only when the hole set, color or shape changes', () {
      final a = painter();
      expect(a.shouldRepaint(painter()), isFalse);
      expect(
        a.shouldRepaint(
          painter(holes: const [Rect.fromLTWH(0, 0, 10, 10)]),
        ),
        isTrue,
      );
      expect(a.shouldRepaint(painter(color: const Color(0x80000000))), isTrue);
      expect(
          a.shouldRepaint(painter(focusShape: FocusShape.roundedRect)), isTrue);
    });
  });
}
