/// hintful — the package's public contract.
///
/// Single import point: `package:hintful/hintful.dart`. Only the public
/// surface is exported:
///
/// - tour data contracts ([HintStep], [HintTour]) — widget-free, serializable
///   1-to-1 to JSON ([HintTour.fromJson] / [HintTour.toJson] — bring your
///   own HTTP client);
/// - target registry ([HintTargetRegistry]) — the "no GlobalKey" model
///   (the register-path and [HintTargetRegistration] are internal — drive
///   targets through [HintTarget]);
/// - observable machine state ([HintState] + subtypes) — the public
///   observable; events/effects/the machine itself are NOT exported;
/// - app-wide configuration ([Hintful]) — the single place to install the
///   versioned-hints store (`Hintful.configure(store: ...)`);
/// - controller ([HintController]) — the single control point; the render
///   contract (`HintOverlayHost`, position types, the overlay factory) is
///   deliberately internal and can change without breaking changes;
/// - diagnostics ([HintDiagnosticsHandler] as a plain function type,
///   [HintSkipEvent], [HintSkipReason]) — failed shows arrive as one event
///   object; debug builds always print the line, then invoke your callback;
/// - theme ([HintTheme], [HintTooltipLabels]) and widgets ([HintTarget],
///   [DefaultTooltip], the "Want a tour?" pre-dialog [showHintTourOffer]);
/// - versioned-hints store ([HintStore], [InMemoryHintStore],
///   [CallbackHintStore], [HintMarkPolicy]) — the "show once per app version"
///   service; configure it once app-wide via `Hintful.configure(store: ...)`.
///
/// Deliberately NOT exported — overlay internals (`HintOverlayEngine`,
/// `HintOverlayHost`, `defaultOverlayHost`, position value types
/// `HintPosition`/`PositionedHint`/`UnpositionedHint`/
/// `HintPositionResolver`), the register-path
/// (`HintTargetRegistration`/`register`/`unregister`/`lookup`), the
/// inheritance-scope helpers (`HintStepInternal` /
/// `resolveTimeout`,
/// `HintControllerScope` / `inScope`), the diagnostics helpers
/// (`formatHintSkipped`, `debugPrintHintSkip`, `closestTargetIds`,
/// `editDistance`), the focus-padding fallback constant `kHintFocusPadding`,
/// the internal `hintTourWithSteps`, and the concrete resolvers
/// `CompositorHintResolver` / `UnpositionedHintResolver` (they touch
/// Flutter's layer internals). They stay public inside `lib/src/` for the
/// package's own tests — a public member of an exported *class* is API by
/// definition, so engine-only helpers live in unexported *extensions*.
///
/// Deep imports (`package:hintful/engine/...`, `package:hintful/widgets/...`)
/// are NOT part of the contract — the implementation lives under `lib/src/`
/// and is only reachable through this barrel.
library;

export 'src/engine/config.dart' show Hintful;
export 'src/engine/controller.dart' show HintController;
export 'src/engine/diagnostics.dart'
    show HintDiagnosticsHandler, HintSkipEvent, HintSkipReason;
export 'src/engine/labels.dart' show HintTourOfferLabels, HintTooltipLabels;
export 'src/engine/machine.dart'
    show HintActive, HintIdle, HintState, HintWaiting;
export 'src/engine/registry.dart' show HintTargetRegistry;
export 'src/engine/specs.dart'
    show
        FocusShape,
        HintActions,
        HintMissingTargetPolicy,
        HintStep,
        HintStepContent,
        HintTapBehavior,
        HintTooltip,
        HintTooltipContext,
        HintTour,
        TooltipPosition;
export 'src/engine/store.dart'
    show CallbackHintStore, HintMarkPolicy, HintStore, InMemoryHintStore;
export 'src/engine/theme/hint_theme.dart' show HintTheme, HintThemeX;
export 'src/widgets/default_tooltip.dart' show DefaultTooltip;
export 'src/widgets/hint_target.dart' show HintTarget;
export 'src/widgets/hint_target_ext.dart' show HintTargetX;
export 'src/widgets/tour_offer.dart'
    show HintTourOfferResult, showHintTourOffer;
