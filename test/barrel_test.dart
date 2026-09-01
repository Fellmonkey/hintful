import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

/// Compile-time contract of the public barrel: the test uses every exported
/// symbol — if an export disappears from `hintful.dart`, this file stops
/// compiling and the contract breaks loudly.
void main() {
  test('barrel: the whole public contract is reachable from one import point',
      () {
    // Tour data (specs).
    const step = HintStep(targetId: 'stats', title: 'Title');
    final tour = HintTour(id: 'intro', steps: [step]);
    expect(step.position, TooltipPosition.auto);
    expect(tour.steps[0].targetId, 'stats');

    // Registry + controller (headless: no overlay host).
    final registry = HintTargetRegistry();
    final controller = HintController(registry: registry);
    addTearDown(controller.dispose);
    expect(registry.ids, isEmpty);
    expect(controller.currentState, isA<HintIdle>());

    // Machine states — the public observable (HintState + subtypes).
    expect(HintWaiting(tour: tour, stepIndex: 0), isA<HintState>());
    expect(HintActive(tour: tour, stepIndex: 0), isA<HintState>());

    // Diagnostics.
    final handler = DebugPrintDiagnostics();
    expect(handler, isA<HintDiagnosticsHandler>());
    expect(HintSkipReason.timeout.label, isNotEmpty);
    expect(findClosestTargetId('statsPeriodSelectr', {'statsPeriodSelector'}),
        'statsPeriodSelector');

    // Theme — zero-config default from ColorScheme.
    final theme = HintTheme.minimal(
      ColorScheme.fromSeed(seedColor: Colors.teal),
    );
    expect(theme, isA<HintTheme>());

    // Widgets.
    expect(HintTarget, same(HintTarget));
    expect(DefaultTooltip, same(DefaultTooltip));

    // Position resolver — for custom hosts.
    expect(const PositionedHint(translation: Offset.zero, size: Size.zero),
        isA<HintPosition>());
    expect(const UnpositionedHint(), isA<HintPosition>());
  });
}
