import 'package:flutter/material.dart';

/// The same scene as [BenchmarkApp] — but with zero hintful in the bundle.
/// Baseline for `tool/bundle_delta.sh`: diff(engine build − this) =
/// hintful's startup-bundle cost. Keep it structurally in sync with
/// [BenchmarkApp].
void main() => runApp(const _BaselineApp());

class _BaselineApp extends StatelessWidget {
  const _BaselineApp();

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    return MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Benchmark'),
          actions: [
            IconButton(
              tooltip: 'Show tour',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () {},
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Log a set'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Workouts', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            for (var i = 0; i < 12; i++)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.fitness_center)),
                title: Text('Entry $i'),
              ),
          ],
        ),
      ),
    );
  }
}
