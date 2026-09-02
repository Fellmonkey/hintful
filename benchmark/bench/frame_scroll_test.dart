import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';
import 'package:integration_test/integration_test.dart';

import 'package:benchmark/benchmark_harness.dart';
import 'package:benchmark/benchmark_utils.dart';
import 'helpers.dart';

/// M4 — frame cost of scrolling while a tour is active.
///
/// The scrim hole and the tooltip follow the target via `LayerLink` — the
/// position comes from the compositor each frame, so scrolling must not
/// force a re-layout of the whole overlay (only the follower re-paints).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scroll frames under an active tour', (tester) async {
    final controller = HintController(overlayHostBuilder: defaultOverlayHost());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      BenchmarkApp(controller: controller, tour: benchmarkTour()),
    );
    await tester.pump();

    controller.start(benchmarkTour());
    await pumpUntilFound(tester, find.text('Step one'));

    final scrollable = find.byType(Scrollable).first;
    final window = await collectFrames(() async {
      // One drag + one settle frame per step, 5 down / 5 up.
      for (var i = 0; i < 5; i++) {
        await tester.drag(scrollable, const Offset(0, -160));
        await tester.pump();
      }
      for (var i = 0; i < 5; i++) {
        await tester.drag(scrollable, const Offset(0, 160));
        await tester.pump();
      }
    });

    // ignore: avoid_print
    print('benchmark_frame_scroll: $window');
    reportMetric('frame_scroll', window.avgBuildUs.round());

    expect(window.timings, isNotEmpty, reason: 'frames were measured');
    expect(
      window.avgBuildUs,
      lessThan(kFrameBudgetUs * 3),
      reason: 'scroll frames under a tour stay cheap even in debug',
    );

    controller.skip();
    // Flush the hide animation and any pending focus work before the test
    // binding is torn down — the drags leave a scheduled frame that would
    // otherwise throw "A FocusManager was used after being disposed" in
    // teardown (seen on CI with a fresh emulator session).
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  });
}
