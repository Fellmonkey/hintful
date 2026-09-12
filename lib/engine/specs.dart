import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart';

/// Preferred side of the tooltip relative to its target.
///
/// The side is re-evaluated live: placement (auto-flip, keep-in-safe-area)
/// is recomputed from the target's current rect on every movement frame, so
/// an explicit side mirrors when it stops fitting and [TooltipPosition.auto]
/// re-picks the side with the most free space.
enum TooltipPosition { auto, top, bottom, left, right }

enum FocusShape { rectangle, circle, roundedRect }

/// Tooltip entry animation — the preset ladder, rung 2 of the animation
/// ladder.
///
/// - null — no entry animation: the tooltip simply appears (the default);
/// - [HintCurve.easeOut] — the quiet preset: fade + a whisper of scale
///   (0.96 → 1) on `Curves.easeOut`, 200 ms;
/// - [HintCurve.sprung] — the bounce: scale 0.8 → 1 on `Curves.elasticOut`
///   (the overshoot is the bounce), 800 ms.
///
/// Each preset's length is overridable per step with
/// [HintStep.transitionDuration], and every preset is skipped under the system
/// reduce-motion setting. Anything beyond a preset (slide, staggered content,
/// a custom button) is rung 3: a `tooltipBuilder` with its own animation
/// widgets — the engine places the built tooltip, the builder owns how it
/// enters.
enum HintCurve { easeOut, sprung }

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

/// What to do when a step's target never appears within its wait timeout.
///
/// - [abortTour] (default) — the tour ends with a `timeout` diagnosis.
/// - [skipStep] — the step is diagnosed and the tour continues with the next
///   one; skipping the last step finishes the tour. For conditionally-absent
///   targets pair with a short `waitTimeout` (`Duration.zero` skips instantly,
///   no waiting flash).
enum HintMissingTargetPolicy { abortTour, skipStep }

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
    this.titleBuilder,
    this.descriptionBuilder,
    this.position = TooltipPosition.auto,
    this.waitTimeout,
    this.showSkip = true,
    this.missingTargetPolicy,
    this.tapOnTarget = true,
    this.tapOnOverlay = true,
    this.onTapTarget,
    this.onTapOverlay,
    this.tooltipBuilder,
    this.focusShape,
    this.focusPadding,
    this.autoScroll,
    this.transitionDuration,
    this.transitionCurve,
    this.targetRect,
    this.onBeforeAction,
    this.onAfterAction,
  })  : assert(targetId != '', 'HintStep.targetId must not be empty'),
        assert(
          title != null ||
              titleBuilder != null ||
              tooltipBuilder != null,
          'HintStep must have title/description (zero-config), '
          'titleBuilder/descriptionBuilder (l10n) or tooltipBuilder'
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

  /// Localized builders; called with the overlay's BuildContext at show
  /// time. Takes precedence over [title]/[description] — use for l10n:
  /// `titleBuilder: (c) => AppLocalizations.of(c)!.introTitle`.
  final String Function(BuildContext)? titleBuilder;
  final String Function(BuildContext)? descriptionBuilder;

  final TooltipPosition position;

  /// Wait-for-target timeout for this step; null — inherits [HintTour.stepTimeout].
  final Duration? waitTimeout;

  /// Whether the default tooltip shows a "Skip" button on this step.
  /// Ignored on the last step of a tour (and on a single-step tour/hint):
  /// the tour is about to end anyway — "Done" does the same, so a "Skip"
  /// next to it would be redundant. Shown on intermediate steps only, and
  /// only when this flag is true.
  final bool showSkip;

  /// Missing-target policy for this step; null — inherits
  /// [HintTour.missingTargetPolicy].
  final HintMissingTargetPolicy? missingTargetPolicy;

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

  /// Hole shape for this step; null — inherits from [HintTarget] or
  /// defaults to [FocusShape.rectangle]. Set on the target for round
  /// icons to avoid per-step duplication — a step override is for the
  /// exception, not the rule.
  final FocusShape? focusShape;
  final double? focusPadding;

  /// Auto-scroll the primary target into view when the step activates.
  /// null — inherits from [HintTour.autoScroll]; `false` by default —
  /// the engine never moves content unless you opt in.
  final bool? autoScroll;

  /// Effective title/description for the overlay's BuildContext at show
  /// time. Builders take precedence — use for l10n without threading
  /// BuildContext through AppTours: `titleBuilder: (c) => l10n.of(c).intro`.
  String? effectiveTitle(BuildContext context) =>
      titleBuilder?.call(context) ?? title;
  String? effectiveDescription(BuildContext context) =>
      descriptionBuilder?.call(context) ?? description;

  /// Entry-animation length for [transitionCurve]; null — the preset's own
  /// default (200 ms for [HintCurve.easeOut], 800 ms for [HintCurve.sprung]).
  /// Ignored without a curve.
  final Duration? transitionDuration;

  /// Entry-animation preset, see [HintCurve] (rung 2 of the animation
  /// ladder); null — no animation. Rung 3 (anything custom) is a
  /// [tooltipBuilder] with its own animation widgets.
  final HintCurve? transitionCurve;
  final Rect? targetRect;
  final Future<void> Function()? onBeforeAction;
  final Future<void> Function()? onAfterAction;

  /// All target ids of the step: the primary [targetId] + [moreTargets].
  List<String> get targetIds => [targetId, ...moreTargets];

  bool get hasRectTarget => targetRect != null;

  /// The step's timeout, honoring inheritance.
  Duration resolveTimeout(Duration fallback) => waitTimeout ?? fallback;

  /// The step's missing-target policy, honoring inheritance.
  HintMissingTargetPolicy resolveMissingPolicy(
    HintMissingTargetPolicy tourPolicy,
  ) =>
      missingTargetPolicy ?? tourPolicy;

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        if (moreTargets.isNotEmpty) 'moreTargets': moreTargets,
        if (moreTooltips.isNotEmpty)
          'moreTooltips': moreTooltips.map((t) => t.toJson()).toList(),
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        'position': position.name,
        if (waitTimeout != null) 'waitTimeoutMs': waitTimeout!.inMilliseconds,
        'showSkip': showSkip,
        if (missingTargetPolicy != null)
          'missingTargetPolicy': missingTargetPolicy!.name,
        'tapOnTarget': tapOnTarget,
        'tapOnOverlay': tapOnOverlay,
        if (focusShape != null) 'focusShape': focusShape!.name,
        if (focusPadding != null) 'focusPadding': focusPadding,
        if (autoScroll != null) 'autoScroll': autoScroll,
        if (transitionDuration != null) 'transitionDurationMs': transitionDuration!.inMilliseconds,
        if (transitionCurve != null) 'transitionCurve': transitionCurve!.name,
        if (targetRect != null)
          'targetRect': {'left': targetRect!.left, 'top': targetRect!.top, 'width': targetRect!.width, 'height': targetRect!.height},
      };

  factory HintStep.fromJson(
    Map<String, dynamic> json, {
    void Function(String warning)? onWarning,
  }) =>
      HintStep(
        targetId: json['targetId'] as String,
        moreTargets: (json['moreTargets'] as List?)?.cast<String>() ?? const [],
        moreTooltips: (json['moreTooltips'] as List?)
                ?.map((e) => HintTooltip.fromJson(
                      e as Map<String, dynamic>,
                      onWarning: onWarning,
                    ))
                .toList() ??
            const [],
        title: json['title'] as String?,
        description: json['description'] as String?,
        position: _enumOrDefault(TooltipPosition.values, json['position'],
            TooltipPosition.auto, field: 'position', onWarning: onWarning),
        waitTimeout: json['waitTimeoutMs'] == null ? null : Duration(milliseconds: json['waitTimeoutMs'] as int),
        showSkip: json['showSkip'] as bool? ?? true,
        missingTargetPolicy: _enumOrNull(HintMissingTargetPolicy.values,
            json['missingTargetPolicy'],
            field: 'missingTargetPolicy',
            onWarning: onWarning),
        tapOnTarget: json['tapOnTarget'] as bool? ?? true,
        tapOnOverlay: json['tapOnOverlay'] as bool? ?? true,
        focusShape: _enumOrNull(FocusShape.values, json['focusShape'],
            field: 'focusShape', onWarning: onWarning),
        focusPadding: (json['focusPadding'] as num?)?.toDouble(),
        autoScroll: json['autoScroll'] as bool?,
        transitionDuration: json['transitionDurationMs'] == null ? null : Duration(milliseconds: json['transitionDurationMs'] as int),
        transitionCurve: _enumOrNull(HintCurve.values, json['transitionCurve'],
            field: 'transitionCurve', onWarning: onWarning),
        targetRect: json['targetRect'] == null
            ? null
            : Rect.fromLTWH((json['targetRect']['left'] as num).toDouble(), (json['targetRect']['top'] as num).toDouble(), (json['targetRect']['width'] as num).toDouble(), (json['targetRect']['height'] as num).toDouble()),
      );
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
    this.titleBuilder,
    this.descriptionBuilder,
    this.tooltipBuilder,
  }) : assert(
          title != null ||
              titleBuilder != null ||
              tooltipBuilder != null,
          'HintTooltip must have title/description (zero-config), '
          'titleBuilder/descriptionBuilder (l10n) or '
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

  /// Localized builders; takes precedence over [title]/[description].
  final String Function(BuildContext)? titleBuilder;
  final String Function(BuildContext)? descriptionBuilder;

  String? effectiveTitle(BuildContext context) =>
      titleBuilder?.call(context) ?? title;
  String? effectiveDescription(BuildContext context) =>
      descriptionBuilder?.call(context) ?? description;

  /// Fully custom content.
  final Widget Function(
    BuildContext context,
    HintStep step,
    HintTooltipContext ctx,
  )? tooltipBuilder;

  Map<String, dynamic> toJson() => {
        'position': position.name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      };

  factory HintTooltip.fromJson(
    Map<String, dynamic> json, {
    void Function(String warning)? onWarning,
  }) =>
      HintTooltip(
        position: _enumOrDefault(TooltipPosition.values, json['position'],
            TooltipPosition.auto, field: 'position', onWarning: onWarning),
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
}

/// A hint tour — a declarative sequence of [HintStep]s.
///
/// Pure data, serializable 1-to-1 to JSON (server-driven tours via
/// `fromJson`): `{id, steps: [{targetId, title, ...}], stepTimeout}`.
@immutable
class HintTour {
  const HintTour({
    required this.id,
    required this.steps,
    this.stepTimeout = const Duration(seconds: 3),
    this.disableBackButton = false,
    this.missingTargetPolicy = HintMissingTargetPolicy.abortTour,
    this.autoScroll = false,
  })  : assert(id != '', 'HintTour.id must not be empty'),
        assert(steps.length > 0, 'HintTour.steps must not be empty');

  final String id;
  final List<HintStep> steps;

  /// Default wait-for-target timeout for all steps of the tour.
  final Duration stepTimeout;

  /// Default missing-target policy for all steps ([HintStep.missingTargetPolicy]
  /// overrides per step): abort the tour, or show every step whose target
  /// exists ([HintMissingTargetPolicy.skipStep]).
  final HintMissingTargetPolicy missingTargetPolicy;

  /// Block the system back button (Android back / route pop) while the tour
  /// is active, instead of letting it dismiss the app/screen mid-tour.
  /// Implemented by intercepting the route pop in the overlay host, so it
  /// works for any Flutter version (no PopScope dependency — which would
  /// also be ineffective inside an OverlayEntry anyway).
  final bool disableBackButton;

  /// Auto-scroll the primary target into view when a step activates.
  /// `false` by default — the engine never moves content unless you opt in.
  /// Per-step [HintStep.autoScroll] overrides this tour default.
  final bool autoScroll;

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
    HintMissingTargetPolicy missingTargetPolicy =
        HintMissingTargetPolicy.abortTour,
    bool autoScroll = false,
  }) {
    return HintTour(
      id: id,
      steps: [for (final value in values) stepFor(value)],
      stepTimeout: stepTimeout,
      disableBackButton: disableBackButton,
      missingTargetPolicy: missingTargetPolicy,
      autoScroll: autoScroll,
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'steps': steps.map((s) => s.toJson()).toList(),
        'stepTimeoutMs': stepTimeout.inMilliseconds,
        'disableBackButton': disableBackButton,
        'missingTargetPolicy': missingTargetPolicy.name,
        if (autoScroll) 'autoScroll': true,
      };

  factory HintTour.fromJson(
    Map<String, dynamic> json, {
    void Function(String warning)? onWarning,
  }) =>
      HintTour(
        id: json['id'] as String,
        steps: (json['steps'] as List)
            .map((step) => HintStep.fromJson(
                  step as Map<String, dynamic>,
                  onWarning: onWarning,
                ))
            .toList(),
        stepTimeout: json['stepTimeoutMs'] == null
            ? const Duration(seconds: 3)
            : Duration(milliseconds: json['stepTimeoutMs'] as int),
        disableBackButton: json['disableBackButton'] as bool? ?? false,
        autoScroll: json['autoScroll'] as bool? ?? false,
        missingTargetPolicy: _enumOrDefault(HintMissingTargetPolicy.values,
            json['missingTargetPolicy'], HintMissingTargetPolicy.abortTour,
            field: 'missingTargetPolicy', onWarning: onWarning),
      );
}

/// Enum value from a JSON [name]: null when the field is absent, null + a
/// warning when the name is unknown.
///
/// A payload is untrusted input — a stale or hand-edited tour must not crash
/// the app — so an unknown value falls back to the field's default and the
/// problem is reported: `debugPrint` in debug builds, plus the optional
/// `onWarning` callback the `fromJson` entry points thread down.
T? _enumOrNull<T extends Enum>(
  List<T> values,
  Object? name, {
  required String field,
  void Function(String warning)? onWarning,
}) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  final warning = "hintful: unknown $field '$name' — using the default";
  if (kDebugMode) debugPrint(warning);
  onWarning?.call(warning);
  return null;
}

/// [_enumOrNull] for a non-nullable field: same warning, the field's
/// [fallback] instead of null.
T _enumOrDefault<T extends Enum>(
  List<T> values,
  Object? name,
  T fallback, {
  required String field,
  void Function(String warning)? onWarning,
}) =>
    _enumOrNull<T>(values, name, field: field, onWarning: onWarning) ??
    fallback;
