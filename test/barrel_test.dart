import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

/// Compile-time contract of the public barrel: this file references every
/// symbol `hintful.dart` exports, so narrowing the barrel stops it from
/// compiling — the symbol simply stops resolving here.
///
/// What stays outside the barrel on purpose (the log formatter `formatHintSkipped`,
/// the `editDistance` metric, the concrete `CompositorHintResolver` /
/// `UnpositionedHintResolver`) is covered through its source path in the engine
/// tests.
void main() {
  test('barrel: the whole public contract is reachable from one import point',
      () async {
    // Tour data (specs).
    const step = HintStep(targetId: 'stats', title: 'Title');
    final tour = HintTour(id: 'intro', steps: [step]);
    expect(step.position, TooltipPosition.auto);
    expect(tour.steps[0].targetId, 'stats');
    expect(tour.missingTargetPolicy, HintMissingTargetPolicy.abortTour);

    // Specs, part two: extra content, the shape/curve enums, JSON round-trip.
    const extra = HintTooltip(position: TooltipPosition.left, title: 'Extra');
    final richTour = HintTour(
      id: 'rich',
      steps: [
        HintStep(targetId: 'stats', title: 'Stats', moreTooltips: [extra]),
      ],
    );
    final restored = HintTour.fromJson(richTour.toJson());
    expect(restored.steps.single.moreTooltips.single.position,
        TooltipPosition.left);
    expect(FocusShape.values, contains(FocusShape.circle));
    expect(HintCurve.values, contains(HintCurve.sprung));

    // Registry + controller (headless: no overlay host).
    final registry = HintTargetRegistry();
    final controller = HintController(registry: registry);
    addTearDown(controller.dispose);
    expect(registry.ids, isEmpty);
    expect(controller.currentState, isA<HintIdle>());
    expect(controller.isIdle, isTrue);
    expect(controller.inScope('anything'), isTrue);

    // Machine states — the public observable (HintState + subtypes).
    expect(HintWaiting(tour: tour, stepIndex: 0), isA<HintState>());
    expect(HintActive(tour: tour, stepIndex: 0), isA<HintState>());

    // Diagnostics.
    final handler = DebugPrintDiagnostics();
    expect(handler, isA<HintDiagnosticsHandler>());
    expect(HintSkipReason.timeout.label, isNotEmpty);
    expect(closestTargetIds('statsPeriodSelectr', {'statsPeriodSelector'}),
        ['statsPeriodSelector']);

    // Actions + tooltip context — what a custom tooltip is handed.
    expect(controller, isA<HintActions>());
    final ctx = HintTooltipContext(
      actions: controller,
      stepIndex: 0,
      totalSteps: 1,
    );
    expect(ctx.isLast, isTrue);

    // Reduce-motion helper — shared by the entry presets and custom tooltips.
    expect(
        hintTransitionDuration(const MediaQueryData(disableAnimations: true),
            const Duration(milliseconds: 120)),
        Duration.zero);
    expect(
        hintTransitionDuration(
            const MediaQueryData(), const Duration(milliseconds: 120)),
        const Duration(milliseconds: 120));

    // Theme — zero-config default from ColorScheme.
    final theme = HintTheme.minimal(
      ColorScheme.fromSeed(seedColor: Colors.teal),
    );
    expect(theme, isA<HintTheme>());
    expect(theme.tooltipLabels, const HintTooltipLabels());
    expect(const HintTooltipLabels().next, 'Next');
    expect(ThemeData().hintTheme, isA<HintTheme>()); // HintThemeX

    // Widgets, widget sugar and the custom-host contract.
    expect(HintTarget, same(HintTarget));
    expect(DefaultTooltip, same(DefaultTooltip));
    expect(
        const SizedBox().withHint('sugar'), isA<HintTarget>()); // HintTargetX
    HintTargetRegistration? registration; // needs a live context to build
    expect(registration, isNull);
    expect(HintOverlayHost, isNotNull);
    expect(
        defaultOverlayHost(), isA<HintOverlayHost Function(HintController)>());

    // Position resolver — for custom hosts.
    expect(const PositionedHint(translation: Offset.zero, size: Size.zero),
        isA<HintPosition>());
    expect(const UnpositionedHint(), isA<HintPosition>());
    expect(HintPositionResolver, isNotNull);

    // Versioned hints — the store service.
    final store = InMemoryHintStore();
    expect(store, isA<HintStore>());
    expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue);
    store.markShown('intro', '1.0.0');
    expect(store.shouldShow('intro', minVersion: '1.0.0'), isFalse);
    expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));

    // Server-driven tours — one interface, two implementations.
    final HintTourFactory inMemory = InMemoryHintTourFactory({'intro': tour});
    expect(await inMemory.fetch('intro'), same(tour));
    final FetcherHintTourFactory fetcher = FetcherHintTourFactory(
      baseUrl: 'https://cdn.example.com/tours',
      fetcher: (uri) async => '{}',
    );
    expect(fetcher, isA<HintTourFactory>());

    // Offer dialog — labels and result types (the call itself needs a context).
    expect(const HintTourOfferLabels().acceptLabel, 'Start');
    expect(HintTourOfferResult.values, hasLength(2));
    expect(showHintTourOffer, isNotNull);
  });
}
