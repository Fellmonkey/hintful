import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';
import 'package:integration_test/integration_test.dart';

import 'package:benchmark/benchmark_harness.dart';
import 'package:benchmark/benchmark_utils.dart';
import 'helpers.dart';

/// M3 — frame cost of step transitions (next/previous).
///
/// The engine must not re-layout the whole overlay when a step changes:
/// only the mounted overlay's content updates, so every transition frame
/// should stay well inside the 16.6 ms budget.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('next/previous transition frames', (tester) async {
    final controller = HintController(overlayHostBuilder: defaultOverlayHost());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      BenchmarkApp(controller: controller, tour: benchmarkTour()),
    );
    await tester.pump();

    controller.start(benchmarkTour());
    await pumpUntilFound(tester, find.text('Step one'));

    final window = await collectFrames(() async {
      for (var i = 0; i < 6; i++) {
        controller.next();
        await pumpUntilFound(tester, find.text('Step two'));
        controller.previous();
        await pumpUntilFound(tester, find.text('Step one'));
      }
    });

    // ignore: avoid_print
    print('benchmark_frame_step_change: $window');
    reportMetric('frame_step_change', window.avgBuildUs.round());

    expect(window.timings, isNotEmpty, reason: 'frames were measured');
    expect(
      window.avgBuildUs,
      lessThan(kFrameBudgetUs * 3),
      reason: 'a step transition must not cost three frame budgets even in '
          'debug',
    );

    controller.skip();
    await tester.pump();
    // Dispose in-body and settle: focus work must not reach teardown (see
    // teardown_clean_test.dart); addTearDown stays as a safety net.
    controller.dispose();
    await tester.pumpAndSettle();
  });
}
