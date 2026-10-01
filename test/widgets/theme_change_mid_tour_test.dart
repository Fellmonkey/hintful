import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';
import 'package:hintful/src/engine/overlay/tooltip_tail.dart';

/// Regression for the slot cache: the tooltip slots (incl. the tail wrapper)
/// embed the resolved [HintTheme], so a mid-tour theme switch used to refresh
/// the tooltip text (via `Theme.of`) but leave the tail painted with the
/// previous background color.
///
/// The theme is driven by a [ValueNotifier] rather than a button tap: while a
/// tour is active the overlay owns every tap on screen, so tapping any control
/// would advance the tour instead.
class _Themed extends StatelessWidget {
  const _Themed({required this.controller, required this.mode});

  final HintController controller;
  final ValueListenable<ThemeMode> mode;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, themeMode, _) => MaterialApp(
          theme: ThemeData(colorScheme: _light),
          darkTheme: ThemeData(colorScheme: _dark),
          themeMode: themeMode,
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 40,
                  top: 60,
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
              ],
            ),
            floatingActionButton: FloatingActionButton(
              key: const Key('start'),
              onPressed: () => unawaited(controller.showTour(HintTour(
                id: 't',
                steps: const [
                  HintStep(targetId: 'a', content: HintStepContent(title: 'A')),
                ],
              ))),
              child: const Icon(Icons.play_arrow),
            ),
          ),
        ),
      );
}

final ColorScheme _light = ColorScheme.fromSeed(seedColor: Colors.teal);
final ColorScheme _dark = ColorScheme.fromSeed(
  seedColor: Colors.teal,
  brightness: Brightness.dark,
);

TooltipTailPainter? _tail(WidgetTester tester) {
  for (final e in tester.elementList(find.byType(CustomPaint))) {
    final ro = e.findRenderObject();
    if (ro is RenderCustomPaint && ro.painter is TooltipTailPainter) {
      return ro.painter as TooltipTailPainter;
    }
  }
  return null;
}

void main() {
  testWidgets('mid-tour theme change repaints the tail with the new color',
      (tester) async {
    final controller = HintController();
    addTearDown(controller.dispose);
    final mode = ValueNotifier<ThemeMode>(ThemeMode.light);
    addTearDown(mode.dispose);

    await tester.pumpWidget(_Themed(controller: controller, mode: mode));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(controller.state.value, isA<HintActive>());
    expect(find.byType(DefaultTooltip), findsOneWidget);
    expect(_tail(tester)?.color, _light.inverseSurface);

    // Flip the theme mid-tour (as the system dark mode would). MaterialApp
    // animates the theme (AnimatedTheme, 200 ms) — advance past it. A plain
    // pumpAndSettle would never settle: the overlay schedules a post-frame
    // poll every frame while a step is active.
    mode.value = ThemeMode.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byType(DefaultTooltip), findsOneWidget);
    expect(_tail(tester)?.color, _dark.inverseSurface,
        reason: 'the tail follows the new theme, not the cached one');

    // Finish the tour (a tap on the spotlighted target advances it).
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    await tester.pump();
  });
}
