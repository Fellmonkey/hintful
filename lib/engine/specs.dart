import 'package:flutter/widgets.dart';

/// Preferred side of the tooltip relative to its target.
///
/// [TooltipPosition.auto] and the explicit sides are used on step changes
/// (side chosen from a snapshot of the target rect); recomputing placement
/// on scroll is follow-up work.
enum TooltipPosition { auto, top, bottom, left, right }

/// Actions available to a step's content (custom tooltips).
///
/// Published instead of the concrete controller: the data contract (specs)
/// must not depend on the implementation of control (controller) — otherwise
/// there would be a circular dependency between pure data and mechanics.
/// `ShowcaseController` implements this interface; a custom tooltip gets
/// exactly the actions it needs (next/skip/finish).
abstract class TourActions {
  /// Move to the next step (finishes the tour on the last one).
  void next();

  /// Abort the tour (the user chose to skip).
  void skip();

  /// Finish the tour normally.
  void finish();
}

/// Per-step context for tooltip content — default and custom.
///
/// Everything a tooltip needs to render buttons and progress without knowing
/// the controller: actions ([TourActions]) plus the position in the tour.
/// Previously `tooltipBuilder` only received a [StepSpec], so a custom tooltip
/// could not render "2/5" or decide "Done instead of Next"; now it gets the
/// full step context.
@immutable
class StepTooltipContext {
  const StepTooltipContext({
    required this.actions,
    required this.stepIndex,
    required this.totalSteps,
  });

  final TourActions actions;
  final int stepIndex;
  final int totalSteps;

  /// Last step of the tour: Next becomes Done.
  bool get isLast => stepIndex == totalSteps - 1;
}

/// A single tour step — data, not a widget.
///
/// Two content paths: zero-config (`title`/`description`, rendered by the
/// default tooltip from [ShowcaseTheme]) and custom (`tooltipBuilder`, the
/// full-customization ladder). `tooltipBuilder` is the only widget-typed slot
/// in the contract — a deliberate exception to allow fully replacing a tooltip.
@immutable
class StepSpec {
  const StepSpec({
    required this.targetId,
    this.title,
    this.description,
    this.position = TooltipPosition.auto,
    this.waitTimeout,
    this.showSkip = true,
    this.tooltipBuilder,
  })  : assert(targetId != '', 'StepSpec.targetId must not be empty'),
        assert(
          title != null || tooltipBuilder != null,
          'StepSpec must have title/description (zero-config) or tooltipBuilder'
          ' (custom tooltip)',
        );

  /// Key in the target registry — not a GlobalKey.
  final String targetId;

  /// Zero-config title/description; ignored when [tooltipBuilder] is set.
  final String? title;
  final String? description;

  final TooltipPosition position;

  /// Wait-for-target timeout for this step; null — inherits [TourSpec.stepTimeout].
  final Duration? waitTimeout;

  /// Whether the default tooltip shows a "Skip" button on this step.
  final bool showSkip;

  /// Fully custom tooltip. Receives the step itself (styling by targetId)
  /// and a [StepTooltipContext] — actions for buttons plus the position in
  /// the tour (index/count, "is last step").
  final Widget Function(
    BuildContext context,
    StepSpec step,
    StepTooltipContext ctx,
  )? tooltipBuilder;

  /// The step's timeout, honoring inheritance.
  Duration resolveTimeout(Duration fallback) => waitTimeout ?? fallback;
}

/// A tour — a declarative sequence of steps.
///
/// Pure data, serializable 1-to-1 to JSON (server-driven tours later):
/// `{id, steps: [{targetId, title, ...}], stepTimeout}`.
@immutable
class TourSpec {
  const TourSpec({
    required this.id,
    required this.steps,
    this.stepTimeout = const Duration(seconds: 3),
  })  : assert(id != '', 'TourSpec.id must not be empty'),
        assert(steps.length > 0, 'TourSpec.steps must not be empty');

  final String id;
  final List<StepSpec> steps;

  /// Default wait-for-target timeout for all steps of the tour.
  final Duration stepTimeout;

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
