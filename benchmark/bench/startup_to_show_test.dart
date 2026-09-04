// custom.startup_to_show — hintful's own frame-count bench (M5), a
// consumer-owned custom scenario (`custom.*`: own scene, own ref, outside
// the S1–S7 contract templates). The contract S2 measures show latency in WALL ms;
// this bench counts FRAMES from `start()` to the first DefaultTooltip
// frame — deterministic (2 frames: scrim pass + positioning pass) and
// independent of build-mode timing. Not part of the contract scenario set:
// hintful-specific, excluded from rivals and public tables; its golden
// lives under the manifest ref `android-custom` (bench_contract.yaml
// customScenarios:) and is run/gated by `contract run`.
//
// The scene is inline (self-contained): MaterialApp + one HintTarget + a
// start button, mirroring the size targets' minimal shape. No shared
// harness — this file is the whole custom scenario.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_bench_contract/flutter_bench_contract.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('start() → first tooltip frame', (tester) async {
    final controller = HintController(overlayHostBuilder: defaultOverlayHost());
    addTearDown(controller.dispose);
    await tester.pumpWidget(_StartupScene(controller: controller));
    await tester.pump();

    final stopwatch = Stopwatch()..start();
    controller.start(_tour());
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
    reportMetric('custom.startup_to_show', frames);

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
    // Dispose in-body and settle: focus work must not reach teardown;
    // addTearDown stays as a safety net.
    controller.dispose();
    await tester.pumpAndSettle();
  });
}

/// Minimal hintful scene: one anchored target + a start button. The frame
/// count is about the OVERLAY mount path, not the scene contents.
class _StartupScene extends StatelessWidget {
  const _StartupScene({required this.controller});

  final HintController controller;

  void _start() {
    if (controller.currentState.isIdle) {
      controller.start(_tour());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    return MaterialApp(
      theme: ThemeData(
        colorScheme: scheme,
        extensions: [HintTheme.minimal(scheme)],
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Benchmark'),
          actions: [
            IconButton(
              tooltip: 'Show tour',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: _start,
            ),
          ],
        ),
        body: Center(
          child: HintTarget(
            id: 'target',
            child: FilledButton(onPressed: _start, child: const Text('Start')),
          ),
        ),
      ),
    );
  }
}

HintTour _tour() => HintTour(
      id: 'startup',
      steps: [
        HintStep(targetId: 'target', title: 'Step one', description: 'Target'),
      ],
    );
