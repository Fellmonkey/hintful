import 'package:flutter/widgets.dart';

/// Preferred side of the tooltip relative to its target.
///
/// The side is re-evaluated live: placement (auto-flip, keep-in-safe-area)
/// is recomputed from the target's current rect on every movement frame, so
/// an explicit side mirrors when it stops fitting and [TooltipPosition.auto]
/// re-picks the side with the most free space.
enum TooltipPosition { auto, top, bottom, left, right }

/// Actions available to a step's content (custom tooltips).
///
/// Published instead of the concrete controller: the data contract (specs)
/// must not depend on the implementation of control (controller) — otherwise
/// there would be a circular dependency between pure data and mechanics.
/// `HintController` implements this interface; a custom tooltip gets
/// exactly the actions it needs (next/skip/previous/finish).
abstract class HintActions {
  /// Move to the next step (finishes the tour on the last one).
  void next();

  /// Go one step back. A no-op on the first step (and for custom tooltips
  /// that do not want a back action — the default is safe).
  void previous() {}

  /// Abort the tour (the user chose to skip).
  void skip();

  /// Finish the tour normally.
  void finish();
}

/// Per-step context for tooltip content — default and custom.
///
/// Everything a tooltip needs to render buttons and progress without knowing
/// the controller: actions ([HintActions]) plus the position in the tour.
/// Previously `tooltipBuilder` only received a [HintStep], so a custom tooltip
/// could not render "2/5" or decide "Done instead of Next"; now it gets the
/// full step context.
@immutable
class HintTooltipContext {
  const HintTooltipContext({
    required this.actions,
    required this.stepIndex,
    required this.totalSteps,
  });

  final HintActions actions;
  final int stepIndex;
  final int totalSteps;

  /// Last step of the tour: Next becomes Done.
  bool get isLast => stepIndex == totalSteps - 1;
}

/// A single tour step — data, not a widget.
///
/// Two content paths: zero-config (`title`/`description`, rendered by the
/// default tooltip from [HintTheme]) and custom (`tooltipBuilder`, the
/// full-customization ladder). `tooltipBuilder` is the only widget-typed slot
/// in the contract — a deliberate exception to allow fully replacing a tooltip.
@immutable
class HintStep {
  const HintStep({
    required this.targetId,
    this.moreTargets = const [],
    this.moreTooltips = const [],
    this.title,
    this.description,
    this.position = TooltipPosition.auto,
    this.waitTimeout,
    this.showSkip = true,
    this.tapOnTarget = true,
    this.tapOnOverlay = true,
    this.onTapTarget,
    this.onTapOverlay,
    this.tooltipBuilder,
  })  : assert(targetId != '', 'HintStep.targetId must not be empty'),
        assert(
          title != null || tooltipBuilder != null,
          'HintStep must have title/description (zero-config) or tooltipBuilder'
          ' (custom tooltip)',
        );

  /// Key in the target registry — not a GlobalKey.
  final String targetId;

  /// Additional targets spotlighted together with [targetId] (multi-target
  /// step: several elements highlighted at once, one tooltip anchored to the
  /// primary [targetId]). The step enters the active phase only when ALL of
  /// [targetIds] are mounted; a scrim hole is cut over each of them.
  final List<String> moreTargets;

  /// Additional tooltips (multi-content): placed around the primary
  /// target alongside the primary tooltip, each on its own side. The engine
  /// guarantees they do not overlap each other or the spotlighted targets
  /// (keep-in-safe-area applies to every slot).
  final List<HintTooltip> moreTooltips;

  /// Zero-config title/description; ignored when [tooltipBuilder] is set.
  final String? title;
  final String? description;

  final TooltipPosition position;

  /// Wait-for-target timeout for this step; null — inherits [HintTour.stepTimeout].
  final Duration? waitTimeout;

  /// Whether the default tooltip shows a "Skip" button on this step.
  /// Ignored on the last step of a tour (and on a single-step tour/hint):
  /// the tour is about to end anyway — "Done" does the same, so a "Skip"
  /// next to it would be redundant. Shown on intermediate steps only, and
  /// only when this flag is true.
  final bool showSkip;

  /// Whether a tap on a spotlighted target advances the tour (when
  /// [onTapTarget] is not set). Both taps default to "next" — the same
  /// behavior as before region distinction; set false to require an explicit
  /// button/callback.
  final bool tapOnTarget;

  /// Whether a tap on the scrim (outside any target) advances the tour
  /// (when [onTapOverlay] is not set).
  final bool tapOnOverlay;

  /// Tap on a spotlighted target: replaces the default [tapOnTarget]
  /// behavior. Receives the step context (actions + position in the tour)
  /// and the tap details (position — for analytics / micro-interactions).
  final void Function(HintTooltipContext ctx, TapDownDetails details)?
      onTapTarget;

  /// Tap on the scrim (outside any target): replaces the default
  /// [tapOnOverlay] behavior.
  final void Function(HintTooltipContext ctx, TapDownDetails details)?
      onTapOverlay;

  /// Fully custom tooltip. Receives the step itself (styling by targetId)
  /// and a [HintTooltipContext] — actions for buttons plus the position in
  /// the tour (index/count, "is last step").
  final Widget Function(
    BuildContext context,
    HintStep step,
    HintTooltipContext ctx,
  )? tooltipBuilder;

  /// All target ids of the step: the primary [targetId] + [moreTargets].
  List<String> get targetIds => [targetId, ...moreTargets];

  /// The step's timeout, honoring inheritance.
  Duration resolveTimeout(Duration fallback) => waitTimeout ?? fallback;
}

/// An additional tooltip of a step (multi-content): a slot with its own
/// preferred side and content, placed around the primary target alongside the
/// primary tooltip. Informational by default — no action buttons (the primary
/// tooltip owns the tour controls); use [tooltipBuilder] for an interactive
/// slot (it receives the same context as the primary's builder).
@immutable
class HintTooltip {
  const HintTooltip({
    required this.position,
    this.title,
    this.description,
    this.tooltipBuilder,
  }) : assert(
          title != null || tooltipBuilder != null,
          'HintTooltip must have title/description (zero-config) or '
          'tooltipBuilder (custom tooltip)',
        );

  /// Preferred side relative to the primary target. An explicit side is
  /// recommended — auto re-picks by free space and may fight the primary
  /// for the same side. Mirroring still applies when the side does not fit
  /// (and the engine guarantees slots never overlap each other).
  final TooltipPosition position;

  /// Zero-config content; ignored when [tooltipBuilder] is set.
  final String? title;
  final String? description;

  /// Fully custom content.
  final Widget Function(
    BuildContext context,
    HintStep step,
    HintTooltipContext ctx,
  )? tooltipBuilder;
}

/// A hint tour — a declarative sequence of [HintStep]s.
///
/// Pure data, serializable 1-to-1 to JSON (server-driven tours later):
/// `{id, steps: [{targetId, title, ...}], stepTimeout}`.
@immutable
class HintTour {
  const HintTour({
    required this.id,
    required this.steps,
    this.stepTimeout = const Duration(seconds: 3),
    this.disableBackButton = false,
  })  : assert(id != '', 'HintTour.id must not be empty'),
        assert(steps.length > 0, 'HintTour.steps must not be empty');

  final String id;
  final List<HintStep> steps;

  /// Default wait-for-target timeout for all steps of the tour.
  final Duration stepTimeout;

  /// Block the system back button (Android back / route pop) while the tour
  /// is active, instead of letting it dismiss the app/screen mid-tour.
  /// Implemented by intercepting the route pop in the overlay host, so it
  /// works for any Flutter version (no PopScope dependency — which would
  /// also be ineffective inside an OverlayEntry anyway).
  final bool disableBackButton;

  /// A tour whose steps come from an enum: the enum values (in declaration
  /// order) ARE the steps — [stepFor] maps each value to its [HintStep].
  ///
  /// The value is compile-time completeness: the switch in [stepFor] is
  /// exhaustive, so adding or removing an enum value breaks the build and
  /// the tour can never silently drift from the enum. (Dart cannot
  /// enumerate the values of a type parameter — constructors cannot be
  /// generic either — so [values] is passed explicitly: pass
  /// `MyEnum.values`, the type is inferred.)
  static HintTour fromEnum<T extends Enum>({
    required String id,
    required List<T> values,
    required HintStep Function(T value) stepFor,
    Duration stepTimeout = const Duration(seconds: 3),
    bool disableBackButton = false,
  }) {
    return HintTour(
      id: id,
      steps: [for (final value in values) stepFor(value)],
      stepTimeout: stepTimeout,
      disableBackButton: disableBackButton,
    );
  }

  /// Target ids referenced by more than one step — a tour-authoring error
  /// (one tour at a time, a duplicated target is ambiguous). Counts
  /// [HintStep.targetIds] (extras included); repeating an id WITHIN one step
  /// is not a duplicate (the same hole twice is harmless). The check is
  /// cheap and lazy; used by the controller's start-validation.
  Set<String> get duplicateTargetIds {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final step in steps) {
      for (final id in step.targetIds.toSet()) {
        if (!seen.add(id)) {
          duplicates.add(id);
        }
      }
    }
    return duplicates;
  }
}
