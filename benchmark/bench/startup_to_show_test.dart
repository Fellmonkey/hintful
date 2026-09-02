import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';
import 'package:integration_test/integration_test.dart';

import 'package:benchmark/benchmark_harness.dart';
import 'package:benchmark/benchmark_utils.dart';

/// M5 — `start()` → first frame that renders the tooltip.
///
/// Frame-aware: the loop pumps one frame at a time and counts how many
/// until `DefaultTooltip` appears — the scrim shows on frame 1, the tooltip
/// on frame 2. The frame count is the contract; wall-clock depends on the
/// build mode and is only sanity-bound.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('start() → first tooltip frame', (tester) async {
    final controller = HintController(overlayHostBuilder: defaultOverlayHost());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      BenchmarkApp(controller: controller, tour: benchmarkTour()),
    );
    await tester.pump();

    final stopwatch = Stopwatch()..start();
    controller.start(benchmarkTour());
    var frames = 0;
    while (frames < 60 && find.byType(DefaultTooltip).evaluate().isEmpty) {
      await tester.pump();
      frames++;
    }
    stopwatch.stop();

    // ignore: avoid_print
    print('benchmark_startup_to_show: $frames frames to first tooltip '
        'frame, ${stopwatch.elapsedMicroseconds} µs '
        '(${stopwatch.elapsedMilliseconds} ms)');
    reportMetric('startup_to_show', frames);

    expect(
      frames,
      lessThanOrEqualTo(3),
      reason: 'scrim frame + positioning frame; more means a wasted pass',
    );
    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(1000),
      reason: 'debug-build sanity bound, not a contract',
    );

    controller.skip();
    await tester.pump();
    // Dispose in-body and settle: focus work must not reach teardown (see
    // teardown_clean_test.dart); addTearDown stays as a safety net.
    controller.dispose();
    await tester.pumpAndSettle();
  });
}
