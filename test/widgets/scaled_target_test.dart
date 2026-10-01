import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

import 'package:hintful/src/engine/overlay/scrim_painter.dart';

/// Regression for plan 013, Option B: a uniformly scaled target used to punch
/// an unscaled hole (`leaderSize`) and let the resolver's translation stand
/// alone — the scrim/tooltip anchored to the wrong rect. The compositor
/// resolver now scales the size and the primary hole reads it.
class _ScaledScreen extends StatefulWidget {
  const _ScaledScreen();

  @override
  State<_ScaledScreen> createState() => _ScaledScreenState();
}

class _ScaledScreenState extends State<_ScaledScreen> {
  late final HintController _controller = HintController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 40,
              top: 60,
              // topLeft alignment keeps the origin at (40, 60) so the expected
              // hole rect is exact.
              child: Transform.scale(
                scale: 2,
                alignment: Alignment.topLeft,
                child: HintTarget(
                  id: 'a',
                  child: Container(
                    key: const Key('a'),
                    width: 100,
                    height: 50,
                    color: Colors.amber,
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          key: const Key('start'),
          onPressed: () => unawaited(_controller.showTour(HintTour(
            id: 't',
            steps: const [
              HintStep(
                targetId: 'a',
                content: HintStepContent(title: 'A'),
              ),
            ],
          ))),
          child: const Icon(Icons.play_arrow),
        ),
      );
}

List<RectScrimPainter> _scrimPainters(WidgetTester tester) {
  final out = <RectScrimPainter>[];
  for (final e in tester.elementList(find.byType(CustomPaint))) {
    final ro = e.findRenderObject();
    if (ro is RenderCustomPaint && ro.painter is RectScrimPainter) {
      out.add(ro.painter! as RectScrimPainter);
    }
  }
  return out;
}

Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('uniform scale: the scrim hole scales with the target',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _ScaledScreen()));
    await _frames(tester, 3);

    await tester.tap(find.byKey(const Key('start')));
    await _frames(tester, 8); // seed → compositor resolver upgrade → scrim

    expect(find.byType(DefaultTooltip), findsOneWidget);
    final painters = _scrimPainters(tester);
    expect(painters, isNotEmpty);

    // translation (40, 60) & size (100x50 × 2), inflated by the default
    // focus padding (4).
    final hole = painters.first.holes.single;
    expect(hole.left, closeTo(36, 1));
    expect(hole.top, closeTo(56, 1));
    expect(hole.width, closeTo(208, 1));
    expect(hole.height, closeTo(108, 1));

    // Finish so no tour timer outlives the test.
    await tester.tap(find.byKey(const Key('a')));
    await _frames(tester, 3);
  });
}
