import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';
import 'package:integration_test/integration_test.dart';

import 'package:benchmark/benchmark_harness.dart';
import 'package:benchmark/benchmark_utils.dart';
import 'helpers.dart';

/// M2 — weight of an active step: the overlay's real cost in the heap.
///
/// Two layers:
/// (a) structural: on an active step the tooltip + the scrim are mounted
///     ([engineNodes] > 0), and after skip zero again;
/// (b) heap: VM-service snapshot (forced GC) at idle and on step 2 — the
///     metric is the delta, the real byte weight of the scrim + follower +
///     tooltip tree (everything else is byte-identical between the two
///     points). Plain `flutter test` VM runs have no VM service — the heap
///     part degrades to the invariants.
///
/// In-test VM-service connections are proxied by DDS on the host, so
/// `flutter drive` runs need `--no-dds` (same requirement as
/// `integration_test`'s timeline API).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('idle → step 2: overlay heap delta', (tester) async {
    final heap = await VmServiceHeap.connect();
    addTearDown(() => heap?.dispose());
    final controller = HintController(overlayHostBuilder: defaultOverlayHost());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      BenchmarkApp(controller: controller, tour: benchmarkTour()),
    );
    await tester.pump();

    // Idle baseline: zero engine in the tree.
    expect(engineNodes(), 0, reason: 'zero idle cost');

    final idleBytes = heap == null ? null : await heap.usedBytes();
    // ignore: avoid_print
    print('benchmark_memory_active: idle heap = '
        '${idleBytes ?? 'unavailable'} B');

    controller.start(benchmarkTour());
    await pumpUntilFound(tester, find.text('Step one'));
    controller.next();
    await pumpUntilFound(tester, find.text('Step two'));

    // Active step: the tooltip + the scrim are live — one of each for this
    // single-target, single-content tour.
    expect(find.byType(DefaultTooltip), findsOneWidget);
    expect(find.text('Step two'), findsOneWidget);

    final activeBytes = heap == null ? null : await heap.usedBytes();
    if (heap != null && idleBytes != null && activeBytes != null) {
      final delta = activeBytes - idleBytes;
      // ignore: avoid_print
      print('benchmark_memory_active: active heap = $activeBytes B, '
          'delta over idle = $delta B (profile)');
      reportMetric('memory_active', delta);
      expect(
        delta.abs(),
        lessThan(8 * 1024 * 1024),
        reason: 'the overlay must be thin — 8 MB is a very generous debug '
            'sanity bound, the profile contract is far tighter',
      );
    } else {
      // ignore: avoid_print
      print('benchmark_memory_active: heap unavailable (no VM service — run '
          'with `flutter drive --no-dds --profile`) — invariants only');
      reportMetric('memory_active', null);
    }

    // Cleanup: skip removes the overlay again (zero-idle restoration).
    controller.skip();
    await tester.pump();
    expect(engineNodes(), 0);
  });
}
