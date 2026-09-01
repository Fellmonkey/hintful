import 'package:flutter/material.dart';

import 'package:hintful/hintful.dart';

/// Minimal scene for the benchmarks: the engine + targets only.
///
/// Deliberately NOT the full example app — a benchmark must measure the
/// engine, not app bootstrap. The example app pulls in `shared_preferences`
/// (the versioned-intro store), snackbars and demo cards, which (a) makes
/// the numbers depend on unrelated app code and (b) breaks running the
/// benchmark in environments without the platform plugin
/// (`MissingPluginException` on `SharedPreferences.getInstance`).
///
/// The scene: the same shapes as the app — an AppBar trigger, a FAB target,
/// a scrollable list with one more target — nothing else.
class BenchmarkApp extends StatefulWidget {
  const BenchmarkApp({
    super.key,
    required this.controller,
    required this.tour,
  });

  final HintController controller;
  final HintTour tour;

  @override
  State<BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<BenchmarkApp> {
  void _start() {
    if (widget.controller.currentState.isIdle) {
      widget.controller.start(widget.tour);
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
        floatingActionButton: HintTarget(
          id: 'fab',
          child: FloatingActionButton.extended(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Log a set'),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Workouts', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            for (var i = 0; i < 12; i++)
              HintTarget(
                id: 'entry-$i',
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.fitness_center)),
                  title: Text('Entry $i'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The tour the idle benchmark walks: two steps on real targets (the FAB
/// and a list row), so an active step has a scrim hole + tooltip.
HintTour benchmarkTour() => HintTour(
      id: 'bench',
      steps: [
        HintStep(targetId: 'fab', title: 'Step one', description: 'FAB'),
        HintStep(targetId: 'entry-0', title: 'Step two', description: 'Row'),
      ],
    );
