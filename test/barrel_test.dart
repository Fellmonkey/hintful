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
    const step = StepSpec(targetId: 'stats', title: 'Title');
    final tour = TourSpec(id: 'intro', steps: [step]);
    expect(step.position, TooltipPosition.auto);
    expect(tour.steps[0].targetId, 'stats');

    // Registry + controller (headless: no overlay host).
    final registry = TargetRegistry();
    final controller = ShowcaseController(registry: registry);
    addTearDown(controller.dispose);
    expect(registry.ids, isEmpty);
    expect(controller.currentState, isA<TourIdle>());

    // Machine states — the public observable (TourState + subtypes).
    expect(TourWaiting(tour: tour, stepIndex: 0), isA<TourState>());
    expect(TourActive(tour: tour, stepIndex: 0), isA<TourState>());

    // Diagnostics.
    final handler = DebugPrintDiagnostics();
    expect(handler, isA<HintDiagnosticsHandler>());
    expect(HintSkipReason.timeout.label, isNotEmpty);
    expect(findClosestTargetId('statsPeriodSelectr', {'statsPeriodSelector'}),
        'statsPeriodSelector');

    // Theme — zero-config default from ColorScheme.
    final theme = ShowcaseTheme.minimal(
      ColorScheme.fromSeed(seedColor: Colors.teal),
    );
    expect(theme, isA<ShowcaseTheme>());

    // Widgets.
    expect(ShowcaseTarget, same(ShowcaseTarget));
    expect(DefaultTooltip, same(DefaultTooltip));

    // Position resolver — for custom hosts.
    expect(const PositionedTarget(translation: Offset.zero, size: Size.zero),
        isA<TargetPosition>());
    expect(const UnlinkedTarget(), isA<TargetPosition>());
  });
}
