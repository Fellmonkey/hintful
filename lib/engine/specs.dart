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
    this.title,
    this.description,
    this.position = TooltipPosition.auto,
    this.waitTimeout,
    this.showSkip = true,
    this.tooltipBuilder,
  })  : assert(targetId != '', 'HintStep.targetId must not be empty'),
        assert(
          title != null || tooltipBuilder != null,
          'HintStep must have title/description (zero-config) or tooltipBuilder'
          ' (custom tooltip)',
        );

  /// Key in the target registry — not a GlobalKey.
  final String targetId;

  /// Zero-config title/description; ignored when [tooltipBuilder] is set.
  final String? title;
  final String? description;

  final TooltipPosition position;

  /// Wait-for-target timeout for this step; null — inherits [HintTour.stepTimeout].
  final Duration? waitTimeout;

  /// Whether the default tooltip shows a "Skip" button on this step.
  final bool showSkip;

  /// Fully custom tooltip. Receives the step itself (styling by targetId)
  /// and a [HintTooltipContext] — actions for buttons plus the position in
  /// the tour (index/count, "is last step").
  final Widget Function(
    BuildContext context,
    HintStep step,
    HintTooltipContext ctx,
  )? tooltipBuilder;

  /// The step's timeout, honoring inheritance.
  Duration resolveTimeout(Duration fallback) => waitTimeout ?? fallback;
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

  /// Duplicated step targetIds within one tour — a tour-authoring error
  /// (one tour at a time, a duplicated target is ambiguous). The check is
  /// cheap and lazy; used by the controller's start-validation.
  Set<String> get duplicateTargetIds {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final step in steps) {
      if (!seen.add(step.targetId)) {
        duplicates.add(step.targetId);
      }
    }
    return duplicates;
  }
}
