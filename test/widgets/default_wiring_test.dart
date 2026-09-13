import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

/// `HintController()` renders out of the box: the default engine wiring
/// reads `controller.registry` — the default registry both wait logic and
/// rendering share.
void main() {
  testWidgets('HintController() with no wiring args shows the default tooltip',
      (tester) async {
    final controller = HintController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HintTarget(
              id: 'stats',
              child: Container(
                width: 120,
                height: 60,
                color: Colors.blue,
                alignment: Alignment.center,
                child: const Text(
                  'stats',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await controller.start(HintTour(
      id: 'intro',
      steps: [
        HintStep(targetId: 'stats', title: 'Stats', description: 'Numbers.'),
      ],
    ));
    // Two-frame rule: frame 1 draws the scrim, frame 2 the tooltip.
    await tester.pump();
    await tester.pump();

    expect(find.text('Stats'), findsOneWidget);
    expect(controller.currentState, isA<HintActive>());
    controller.finish();
    await tester.pump();
    await tester.pump();
    expect(controller.isIdle, isTrue);
  });

  testWidgets(
      'default host follows a custom controller.registry '
      '(engine and wait logic cannot desync)', (tester) async {
    final registry = HintTargetRegistry();
    final controller = HintController(registry: registry);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HintTarget(
              registry: registry,
              id: 'stats',
              child: Container(
                width: 120,
                height: 60,
                color: Colors.teal,
                alignment: Alignment.center,
                child: const Text(
                  'stats',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await controller.start(HintTour(
      id: 'intro',
      steps: [HintStep(targetId: 'stats', title: 'Scoped')],
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Scoped'), findsOneWidget);
    expect(registry.ids, contains('stats'));
    controller.finish();
    await tester.pump();
    await tester.pump();
    expect(controller.isIdle, isTrue);
  });
}
