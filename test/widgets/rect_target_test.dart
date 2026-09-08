import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/hintful.dart';

/// Rect-anchored steps ([HintStep.targetRect]): the spotlight is cut at
/// explicit coordinates with no registry targets involved.
HintTour _rectTour() => HintTour(
      id: 'rect',
      steps: const [
        HintStep(
          targetId: 'ghost',
          targetRect: Rect.fromLTWH(100, 300, 120, 40),
          title: 'Rect by coords',
          description: 'targetRect — without HintTarget',
        ),
      ],
    );

Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _hasRectScrim(WidgetTester tester) {
  for (final e in tester.elementList(find.byType(CustomPaint))) {
    final ro = e.findRenderObject();
    if (ro is RenderCustomPaint && ro.painter is RectScrimPainter) {
      return true;
    }
  }
  return false;
}

void main() {
  testWidgets('rect step: hole at coords + tooltip, tap hole finishes',
      (tester) async {
    final controller = HintController(
      overlayHostBuilder: defaultOverlayHost(),
    );
    addTearDown(controller.dispose);

    // An unrelated mounted target: the overlay capture anchor (the rect
    // step itself needs no registry targets).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HintTarget(
            id: 'anchor',
            child: Container(
              key: const Key('anchor'),
              width: 50,
              height: 50,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
    await _frames(tester, 3);

    unawaited(controller.start(_rectTour()));
    await _frames(tester, 6);

    expect(find.text('Rect by coords'), findsOneWidget);
    expect(_hasRectScrim(tester), isTrue);

    // Tap inside the rect hole (160, 320) — the target region: finishes.
    await tester.tapAt(const Offset(160, 320));
    await _frames(tester, 3);
    expect(find.text('Rect by coords'), findsNothing);
  });

  testWidgets('rect step with zero targets: explicit overlay renders it',
      (tester) async {
    final overlayKey = GlobalKey<OverlayState>();
    final controller = HintController(
      overlayHostBuilder: defaultOverlayHost(
        overlay: () => overlayKey.currentState,
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: Theme(
          data: ThemeData.light(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(
                  builder: (context) => const Scaffold(
                    body: Center(child: Text('page')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _frames(tester, 3);

    unawaited(controller.start(_rectTour()));
    await _frames(tester, 6);

    // No registry targets at all — yet the rect hole + tooltip render
    // through the explicitly provided overlay.
    expect(find.text('Rect by coords'), findsOneWidget);
    expect(_hasRectScrim(tester), isTrue);

    controller.finish();
    await _frames(tester, 2);
    expect(find.text('Rect by coords'), findsNothing);
  });
}
