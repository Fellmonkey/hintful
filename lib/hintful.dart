/// hintful — the package's public contract.
///
/// Single import point: `package:hintful/hintful.dart`. Only the public
/// surface is exported:
///
/// - tour data contracts ([HintStep], [HintTour]) — widget-free, serializable
///   1-to-1 to JSON (server-driven tours later);
/// - target registry ([HintTargetRegistry], [HintTargetRegistration]) — the
///   "no GlobalKey" model;
/// - observable machine state ([HintState] + subtypes) — the public
///   observable; events/effects/the machine itself are NOT exported;
/// - controller ([HintController]) and the render-mechanics contract
///   ([HintOverlayHost]) — the single control point;
/// - diagnostics ([HintDiagnosticsHandler], [HintSkipReason],
///   [DebugPrintDiagnostics], typo candidates);
/// - theme ([HintTheme]) and widgets ([HintTarget], [DefaultTooltip], the
///   "Want a tour?" pre-dialog [showHintTourOffer]);
/// - position resolver ([HintPositionResolver]) — for custom hosts;
/// - versioned-hints store ([HintStore], [InMemoryHintStore],
///   [compareVersions]) — the "show once per app version" service.
///
/// Deliberately NOT exported is overlay internals ([HintOverlayEngine],
/// scrim painter, placement delegate) — mechanics that can change without
/// breaking changes. Exception — [defaultOverlayHost]: the single public
/// entry into render mechanics, a stable factory for wiring the host (the
/// controller's `overlayHostBuilder`).
library;

export 'engine/controller.dart' show HintController, HintOverlayHost;
export 'engine/diagnostics.dart';
export 'engine/overlay/overlay_engine.dart' show defaultOverlayHost;
export 'engine/machine.dart' show HintActive, HintIdle, HintState, HintWaiting;
export 'engine/position_resolver.dart';
export 'engine/registry.dart';
export 'engine/specs.dart';
export 'engine/store.dart';
export 'engine/theme/hint_theme.dart';
export 'widgets/default_tooltip.dart';
export 'widgets/hint_target.dart';
export 'widgets/tour_offer.dart';
