import 'package:flutter/material.dart';

import 'package:hintful/hintful.dart';

/// Web entry for the S7 size leg (benchmark/bench_contract `size:`
/// section, run by `contract run`): the SAME scene as [main_baseline]
/// (structurally identical: AppBar + play action, extended FAB, 12 rows)
/// plus hintful's engine — controller + targets on the FAB and row 0. The
/// contract CLI diffs this build against the baseline on main.dart.js, so
/// the two targets must stay mirror images except for hintful's presence.
///
/// Native-size target too (size.native): the analyze-size build uses the
/// default target (this file) and reads the `package:hintful` subtree.
void main() {
  runApp(
    _EngineApp(controller: HintController(overlayHostBuilder: defaultOverlayHost())),
  );
}

class _EngineApp extends StatefulWidget {
  const _EngineApp({required this.controller});

  final HintController controller;

  @override
  State<_EngineApp> createState() => _EngineAppState();
}

class _EngineAppState extends State<_EngineApp> {
  void _start() {
    if (widget.controller.currentState.isIdle) {
      widget.controller.start(_tour());
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
            const SizedBox(height: 1200),
          ],
        ),
      ),
    );
  }

  /// Mirrors main_baseline's implicit structure: steps carry title +
  /// description (hintful's default tooltip shape), so the bundle pulls the
  /// same feature set the baseline counterpart would render.
  HintTour _tour() => HintTour(
        id: 'bench',
        steps: [
          HintStep(targetId: 'fab', title: 'Step one', description: 'FAB'),
          HintStep(targetId: 'entry-0', title: 'Step two', description: 'Row'),
        ],
      );
}
