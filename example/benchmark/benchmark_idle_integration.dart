import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/overlay/scrim_painter.dart';
import 'package:hintful/hintful.dart';
import 'package:integration_test/integration_test.dart';

import 'package:hintful_example/main.dart';

/// Benchmark skeleton: checkable invariants on a live device/emulator, not
/// numbers against other libraries (comparison methodology and goldens are
/// future work, see `benchmark/methodology.md`).
///
/// Invariants (a contract, not marketing):
/// (a) idle: zero engine widgets in the tree (scrim/tooltip/follower) —
///     zero idle cost;
/// (b) after start: the scrim hole + the tooltip are found;
/// (c) after finish: zero again.
/// Plus a `Stopwatch` on the mount time: from the "Show tour" tap to the
/// first tooltip frame — a soft bound (not hanging), not a contract.
///
/// The file lives inside the example package (the only app integration_test
/// can run against: it imports `package:hintful_example` + the SDK
/// dependency `integration_test`).
///
/// Run: `cd example && flutter test -d <device> benchmark/benchmark_idle_integration.dart`
/// CI: job `bench-idle`, only main/tag — it is expensive, outside the PR loop.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final scrimFinder = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is ScrimHolePainter,
  );

  testWidgets('idle → active → finish: zero-idle invariants + mount time',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    // (a) idle: zero engine in the tree.
    expect(find.byType(DefaultTooltip), findsNothing, reason: 'no tooltip');
    expect(scrimFinder, findsNothing, reason: 'no scrim');
    expect(find.byType(CompositedTransformFollower), findsNothing,
        reason: 'no follower');
    expect(find.text('Next'), findsNothing);

    // Start the tour; mount time = tap → first tooltip frame.
    final stopwatch = Stopwatch()..start();
    await tester.tap(find.byTooltip('Show tour'));
    await tester.pump(); // frame 1: scrim, position snapshot post-frame
    await tester.pump(); // frame 2: tooltip at the right place
    stopwatch.stop();

    // (b) after start: the scrim hole + the tooltip.
    expect(scrimFinder, findsOneWidget);
    expect(find.text('Quick log'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // A soft bound, not a contract: `flutter test` runs a debug build (the
    // web-debug measurement is ≈ 250 ms), so here just "does not hang"
    // (a wall-clock contract belongs to profile builds, see methodology.md).
    // The value is printed so a regression shows up in the CI log.
    final mountMs = stopwatch.elapsedMilliseconds;
    // ignore: avoid_print
    print('benchmark_idle: mount-time = $mountMs ms (debug, web)');
    expect(mountMs, lessThan(1000), reason: 'debug-build sanity bound');

    // (c) finish (skip): the overlay is removed, zero engine again.
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(find.byType(DefaultTooltip), findsNothing);
    expect(scrimFinder, findsNothing);
    expect(find.byType(CompositedTransformFollower), findsNothing);
    expect(find.text('Next'), findsNothing);
  });
}
