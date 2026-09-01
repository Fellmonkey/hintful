/// hintful — the package's public contract.
///
/// Single import point: `package:hintful/hintful.dart`. Only the public
/// surface is exported:
///
/// - tour data contracts ([StepSpec], [TourSpec]) — widget-free, serializable
///   1-to-1 to JSON (server-driven tours later);
/// - target registry ([TargetRegistry], [TargetRegistration]) — the
///   "no GlobalKey" model;
/// - observable machine state ([TourState] + subtypes) — the public
///   observable; events/effects/the machine itself are NOT exported;
/// - controller ([ShowcaseController]) and the render-mechanics contract
///   ([TourOverlayHost]) — the single control point;
/// - diagnostics ([HintDiagnosticsHandler], [HintSkipReason],
///   [DebugPrintDiagnostics], typo candidates);
/// - theme ([ShowcaseTheme]) and widgets ([ShowcaseTarget], [DefaultTooltip]);
/// - position resolver ([TargetPositionResolver]) — for custom hosts.
///
/// Deliberately NOT exported is overlay internals ([TourOverlayEngine],
/// scrim painter, placement delegate) — mechanics that can change without
/// breaking changes. Exception — [defaultOverlayHost]: the single public
/// entry into render mechanics, a stable factory for wiring the host (the
/// controller's `overlayHostBuilder`).
library;

export 'engine/controller.dart' show ShowcaseController, TourOverlayHost;
export 'engine/diagnostics.dart';
export 'engine/overlay/overlay_engine.dart' show defaultOverlayHost;
export 'engine/machine.dart' show TourActive, TourIdle, TourState, TourWaiting;
export 'engine/position_resolver.dart';
export 'engine/registry.dart';
export 'engine/specs.dart';
export 'engine/theme/showcase_theme.dart';
export 'widgets/default_tooltip.dart';
export 'widgets/showcase_target.dart';
