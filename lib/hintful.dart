/// hintful — the package's public contract.
///
/// Single import point: `package:hintful/hintful.dart`. Only the public
/// surface is exported:
///
/// - tour data contracts ([HintStep], [HintTour]) — widget-free, serializable
///   1-to-1 to JSON (server-driven tours via `fromJson`);
/// - target registry ([HintTargetRegistry], [HintTargetRegistration]) — the
///   "no GlobalKey" model;
/// - observable machine state ([HintState] + subtypes) — the public
///   observable; events/effects/the machine itself are NOT exported;
/// - motion ([hintTransitionDuration]) — the reduce-motion helper the entry
///   presets and custom tooltips share;
/// - controller ([HintController]) and the render-mechanics contract
///   ([HintOverlayHost]) — the single control point;
/// - diagnostics ([HintDiagnosticsHandler], [HintSkipReason],
///   [DebugPrintDiagnostics]) and the typo search ([closestTargetIds]);
/// - theme ([HintTheme], [HintTooltipLabels]) and widgets ([HintTarget], [DefaultTooltip], the
///   "Want a tour?" pre-dialog [showHintTourOffer]);
/// - position value types ([HintPosition], [PositionedHint],
///   [UnpositionedHint]) and the [HintPositionResolver] contract — for custom
///   hosts;
/// - versioned-hints store ([HintStore], [InMemoryHintStore],
///   [compareVersions]) — the "show once per app version" service.
///
/// Deliberately NOT exported is overlay internals ([HintOverlayEngine],
/// scrim painter, placement delegate) — mechanics that can change without
/// breaking changes. Exception — [defaultOverlayHost]: the single public
/// entry into render mechanics, a stable factory for wiring the host (the
/// controller's `overlayHostBuilder`).
///
/// Also outside the contract, for the same reason: the diagnostics helpers
/// `formatHintSkipped` (the exact log line is not an API) and `editDistance`
/// (a generic string metric), and the concrete resolvers
/// `CompositorHintResolver` / `UnpositionedHintResolver` (they touch
/// Flutter's layer internals). They stay public inside `lib/engine/` for the
/// package's own tests.
library;

export 'engine/controller.dart' show HintController, HintOverlayHost;
export 'engine/diagnostics.dart'
    show
        DebugPrintDiagnostics,
        HintDiagnosticsHandler,
        HintSkipReason,
        closestTargetIds;
export 'engine/labels.dart';
export 'engine/overlay/overlay_engine.dart' show defaultOverlayHost;
export 'engine/machine.dart' show HintActive, HintIdle, HintState, HintWaiting;
export 'engine/motion.dart' show hintTransitionDuration;
export 'engine/position_resolver.dart'
    show HintPosition, HintPositionResolver, PositionedHint, UnpositionedHint;
export 'engine/registry.dart';
export 'engine/specs.dart';
export 'engine/store.dart';
export 'engine/theme/hint_theme.dart';
export 'engine/tour_factory.dart';
export 'widgets/default_tooltip.dart';
export 'widgets/hint_target.dart';
export 'widgets/hint_target_ext.dart';
export 'widgets/tour_offer.dart';
