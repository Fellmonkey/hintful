import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

// Internal painter — same package, importable in tests.
import 'package:hintful/engine/overlay/scrim_painter.dart';

/// Regression: the first shown step rendered "tooltip without dim".
///
/// The scrim painter is built with `_resolverList()` evaluated at build time
/// (empty — no follower is composed yet), while the live resolvers appear
/// only in the post-frame position poll. The poll mounted the tooltip via
/// `_holeNotifier` but never rebuilt the scrim widget, so it kept the empty
/// snapshot list and painted nothing until a step change rebuilt it.
class _SyncScreen extends StatefulWidget {
  const _SyncScreen();

  @override
  State<_SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<_SyncScreen> {
  late final HintController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HintController(overlayHostBuilder: defaultOverlayHost());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          HintTarget(
            id: 'a',
            child: Container(
              key: const Key('a'),
              height: 120,
              color: Colors.amber,
            ),
          ),
          const SizedBox(height: 300),
          HintTarget(
            id: 'b',
            child: Container(
              key: const Key('b'),
              height: 80,
              color: Colors.teal,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('start'),
        onPressed: () => unawaited(_controller.start(HintTour(
          id: 't',
          steps: const [
            HintStep(targetId: 'a', title: 'A', description: 'd'),
            HintStep(targetId: 'b', title: 'B', description: 'd'),
          ],
        ))),
        child: const Icon(Icons.play_arrow),
      ),
    );
  }
}

List<ScrimHolePainter> _scrimPainters(WidgetTester tester) {
  final out = <ScrimHolePainter>[];
  for (final e in tester.elementList(find.byType(CustomPaint))) {
    final ro = e.findRenderObject();
    if (ro is RenderCustomPaint && ro.painter is ScrimHolePainter) {
      out.add(ro.painter! as ScrimHolePainter);
    }
  }
  return out;
}

Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('first shown step: scrim painter holds resolvers', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _SyncScreen()));
    await _frames(tester, 3);
    await tester.tap(find.byKey(const Key('start')));
    await _frames(tester, 6);

    expect(find.byType(DefaultTooltip), findsOneWidget);

    var painters = _scrimPainters(tester);
    expect(painters, isNotEmpty);
    for (final p in painters) {
      expect(p.resolvers, isNotEmpty);
    }

    // Step 2 (tap on the spotlighted target) keeps the scrim wired.
    await tester.tap(find.byKey(const Key('a')));
    await _frames(tester, 6);

    painters = _scrimPainters(tester);
    expect(painters, isNotEmpty);
    for (final p in painters) {
      expect(p.resolvers, isNotEmpty);
    }

    // Finish the tour so no tour timers are left pending at teardown.
    await tester.tap(find.byKey(const Key('b')));
    await _frames(tester, 3);
    expect(find.byType(DefaultTooltip), findsNothing);
  });

  testWidgets('late target (Waiting -> Active): scrim painter holds resolvers',
      (tester) async {
    final controller = HintController(
      overlayHostBuilder: defaultOverlayHost(),
    );
    addTearDown(controller.dispose);
    var showTarget = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                if (showTarget)
                  HintTarget(
                    id: 'late',
                    child: Container(
                      key: const Key('late'),
                      height: 120,
                      color: Colors.amber,
                    ),
                  ),
                TextButton(
                  key: const Key('show'),
                  onPressed: () => setState(() => showTarget = true),
                  child: const Text('show'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _frames(tester, 3);

    // Start while the target is absent -> Waiting (full scrim, no hole).
    unawaited(
      controller.start(
        HintTour(
          id: 't',
          steps: const [
            HintStep(targetId: 'late', title: 'L', description: 'd'),
          ],
        ),
      ),
    );
    await _frames(tester, 3);

    // Mount the target late -> Active with hole.
    await tester.tap(find.byKey(const Key('show')));
    await _frames(tester, 6);

    expect(find.byType(DefaultTooltip), findsOneWidget);
    final painters = _scrimPainters(tester);
    expect(painters, isNotEmpty);
    for (final p in painters) {
      expect(p.resolvers, isNotEmpty);
    }

    // Finish the tour so its wait-timeout timer does not outlive the test.
    controller.finish();
    await _frames(tester, 3);
    expect(find.byType(DefaultTooltip), findsNothing);
  });
}
