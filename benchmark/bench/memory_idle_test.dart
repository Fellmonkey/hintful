import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';
import 'package:integration_test/integration_test.dart';

import 'package:benchmark/benchmark_harness.dart';
import 'package:benchmark/benchmark_utils.dart';
import 'helpers.dart';

/// M1 — zero idle cost + full release after finish.
///
/// Two layers:
/// (a) structural: [engineNodes] (tooltip + scrim) is 0 when no tour runs
///     and 0 again after finish;
/// (b) heap: VM-service snapshot (forced GC) at idle and after finish — the
///     metric is the post-finish drift, which must be ~0 (the overlay left
///     nothing behind). Plain `flutter test` VM runs have no VM service —
///     the heap part degrades to the invariants.
///
/// In-test VM-service connections are proxied by DDS on the host, so
/// `flutter drive` runs need `--no-dds` (same requirement as
/// `integration_test`'s timeline API).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('idle → active → finish: zero-idle + heap release',
      (tester) async {
    final heap = await VmServiceHeap.connect();
    addTearDown(() => heap?.dispose());
    final controller = HintController(overlayHostBuilder: defaultOverlayHost());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        BenchmarkApp(controller: controller, tour: benchmarkTour()));
    await tester.pump();

    final idleBytes = heap == null ? null : await heap.usedBytes();
    // ignore: avoid_print
    print('benchmark_idle: idle heap = ${idleBytes ?? 'unavailable'} B');

    // (a) idle: zero engine in the tree.
    expect(engineNodes(), 0, reason: 'zero idle cost');
    expect(find.text('Next'), findsNothing);

    // Start the tour; mount time = tap → first tooltip frame.
    final stopwatch = Stopwatch()..start();
    await tester.tap(find.byTooltip('Show tour'));
    await tester.pump(); // frame 1: scrim, position snapshot post-frame
    await tester.pump(); // frame 2: tooltip at the right place
    stopwatch.stop();

    // Active: the scrim + the tooltip are mounted.
    expect(engineNodes(), greaterThan(0), reason: 'overlay is live');
    expect(find.text('Step one'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // A soft bound, not a contract (debug builds are slower than profile).
    final mountMs = stopwatch.elapsedMilliseconds;
    // ignore: avoid_print
    print('benchmark_idle: mount-time = $mountMs ms (debug)');
    expect(mountMs, lessThan(1000), reason: 'debug-build sanity bound');

    // (c) finish (skip): overlay removed, zero engine again, and the heap is
    // back at the idle baseline.
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(engineNodes(), 0, reason: 'finish unmounts the whole overlay');

    // Flush the hide animation and any pending focus work before the heap
    // read and teardown — a leftover scheduled frame would otherwise throw
    // "A FocusManager was used after being disposed" in teardown.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final postBytes = heap == null ? null : await heap.usedBytes();
    if (heap != null && idleBytes != null && postBytes != null) {
      final drift = (postBytes - idleBytes).abs();
      // ignore: avoid_print
      print('benchmark_idle: post-finish heap = $postBytes B, drift from '
          'idle = $drift B (profile)');
      reportMetric('memory_idle', drift);
      expect(
        drift,
        lessThan(8 * 1024 * 1024),
        reason: 'finish must release the overlay — 8 MB is a generous '
            'debug sanity bound, the profile contract is far tighter',
      );
    } else {
      // ignore: avoid_print
      print('benchmark_idle: heap unavailable (no VM service — run with '
          '`flutter drive --no-dds --profile`) — invariants only');
      reportMetric('memory_idle', null);
    }
  });
}
