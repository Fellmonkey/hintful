import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

import 'package:benchmark/benchmark_harness.dart';
import 'helpers.dart';

/// Regression guard for the teardown race seen on CI ("A FocusManager was
/// used after being disposed" after a bench test completes).
///
/// The framework's [TestWidgetsFlutterBinding.postTest] disposes the focus
/// manager right after the teardown callbacks, so any focus change left
/// pending for teardown fires on the disposed instance. The bench tests
/// therefore dispose the controller in-body and settle while the app is
/// alive. This test locks that property: after the canonical ending, the
/// focus manager can be disposed and the microtask queue drained with no
/// exception.
///
/// This is a property lock, not a faithful repro of the live-binding timing
/// (the automated binding drains microtasks deterministically) — but it
/// fails if the ending ever leaves focus work behind.
void main() {
  testWidgets('tour teardown leaves no pending focus work', (tester) async {
    final controller = HintController(overlayHostBuilder: defaultOverlayHost());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      BenchmarkApp(controller: controller, tour: benchmarkTour()),
    );
    await tester.pump();

    controller.start(benchmarkTour());
    await pumpUntilFound(tester, find.text('Step one'));

    // Canonical ending (same as the device benchmarks).
    controller.skip();
    await tester.pump();
    controller.dispose();
    await tester.pumpAndSettle();

    // postTest() equivalent: dispose the focus manager and drain microtasks.
    // Focus changes are scheduled via scheduleMicrotask, so plain awaits
    // drain them (Future.delayed would hang — FakeAsync never fires it).
    // Any pending applyFocusChangesIfNeeded would throw here.
    tester.binding.buildOwner!.focusManager.dispose();
    await null;
    await null;
    // Restore a fresh manager, mirroring postTest, so the framework's own
    // postTest doesn't double-dispose.
    tester.binding.buildOwner!.focusManager =
        FocusManager()..registerGlobalHandlers();

    // Reached = the teardown was clean.
    expect(true, isTrue);
  });
}