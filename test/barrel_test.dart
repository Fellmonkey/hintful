import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/hintful.dart';

/// Compile-time contract of the public barrel: this file references every
/// symbol `hintful.dart` exports, so narrowing the barrel stops it from
/// compiling — the symbol simply stops resolving here.
///
/// What stays outside the barrel on purpose (the render contract
/// `HintOverlayHost`/`defaultOverlayHost`/position types, the register-path
/// `HintTargetRegistration`, the diagnostics helpers `formatHintSkipped`/
/// `DebugPrintDiagnostics`/`closestTargetIds`, `kHintFocusPadding`,
/// `hintTourWithSteps`, and the concrete `CompositorHintResolver` /
/// `UnpositionedHintResolver`) is covered through its source path in the
/// engine tests.
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

    // Content slot type + tap behaviors (1.0 merge of overlapping knobs).
    const content = HintStepContent(title: 'T', description: 'D');
    const sugarStep = HintStep(
      targetId: 'stats',
      title: 'T',
      description: 'D',
    );
    expect(content.title, 'T');
    expect(sugarStep.title, 'T');
    expect(sugarStep.description, 'D');
    expect(sugarStep.content.title, 'T');
    const targetTap = HintTapBehavior.ignore();
    const overlayTap = HintTapBehavior.advance();
    final customTap = HintTapBehavior.custom((ctx, details) {});
    expect(targetTap, isA<HintTapIgnore>());
    expect(overlayTap, isA<HintTapAdvance>());
    expect(customTap, isA<HintTapCustom>());

    // Registry + controller (headless: no overlay host).
    final registry = HintTargetRegistry();
    final controller = HintController(registry: registry, headless: true);
    addTearDown(controller.dispose);
    expect(controller.registry, same(registry));
    expect(registry.ids, isEmpty);
    expect(controller.currentState, isA<HintIdle>());
    expect(controller.isIdle, isTrue);
    expect(controller.inScope('anything'), isTrue);

    // Machine states — the public observable (HintState + subtypes).
    expect(HintWaiting(tour: tour, stepIndex: 0), isA<HintState>());
    expect(HintActive(tour: tour, stepIndex: 0), isA<HintState>());

    // Diagnostics — one event object, extensible in 1.x.
    const event = HintSkipEvent(
      tourId: 'intro',
      stepIndex: 0,
      targetId: 'stats',
      reason: HintSkipReason.timeout,
      detail: 'did not appear',
    );
    expect(event.reason, HintSkipReason.timeout);
    expect(HintSkipReason.timeout.label, isNotEmpty);
    expect(
      _HandlerProbe(),
      isA<HintDiagnosticsHandler>(),
    );

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

    // Widgets and widget sugar.
    expect(HintTarget, same(HintTarget));
    expect(DefaultTooltip, same(DefaultTooltip));
    expect(
        const SizedBox().withHint('sugar'), isA<HintTarget>()); // HintTargetX

    // Versioned hints — the store service + startOnce (method contract).
    final store = InMemoryHintStore();
    expect(store, isA<HintStore>());
    expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue);
    store.markShown('intro', '1.0.0');
    expect(store.shouldShow('intro', minVersion: '1.0.0'), isFalse);
    expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    expect(controller.startOnce, isNotNull); // tear-off resolves via barrel

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

class _HandlerProbe implements HintDiagnosticsHandler {
  @override
  void onHintSkipped(HintSkipEvent event) {}
}
