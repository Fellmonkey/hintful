import 'package:flutter/foundation.dart' show debugPrint, internal, kDebugMode;
import 'package:flutter/widgets.dart';

/// Preferred side of the tooltip relative to its target.
///
/// The side is re-evaluated live: placement (auto-flip, keep-in-safe-area)
/// is recomputed from the target's current rect on every movement frame, so
/// an explicit side mirrors when it stops fitting and [TooltipPosition.auto]
/// re-picks the side with the most free space.
///
/// Closed in 1.x: no new values before 2.0 — exhaustive `switch`es in app
/// code are safe.
enum TooltipPosition { auto, top, bottom, left, right }

/// Hole shape cut into the scrim around a spotlighted target.
///
/// Closed in 1.x: no new values before 2.0 — exhaustive `switch`es in app
/// code are safe.
enum FocusShape { rectangle, circle, roundedRect }

/// Tooltip entry animation — the preset ladder, rung 2 of the animation
/// ladder.
///
/// - null — no entry animation: the tooltip simply appears (the default);
/// - [HintEntryAnimation.easeOut] — the quiet preset: fade + a whisper of scale
///   (0.96 → 1) on `Curves.easeOut`, 200 ms;
/// - [HintEntryAnimation.sprung] — the bounce: scale 0.8 → 1 on `Curves.elasticOut`
///   (the overshoot is the bounce), 800 ms.
///
/// Each preset's length is overridable per step with
/// [HintStep.transitionDuration], and every preset is skipped under the system
/// reduce-motion setting. Anything beyond a preset (slide, staggered content,
/// a custom button) is rung 3: a `tooltipBuilder` with its own animation
/// widgets — the engine places the built tooltip, the builder owns how it
/// enters.
///
/// Closed in 1.x: no new values before 2.0 — exhaustive `switch`es in app
/// code are safe.
enum HintEntryAnimation { easeOut, sprung }

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
///   targets pair with a short per-step `stepTimeout` (`Duration.zero` skips
///   instantly, no waiting flash).
///
/// Closed in 1.x: no new values before 2.0 — exhaustive `switch`es in app
/// code are safe.
enum HintMissingTargetPolicy { abortTour, skipStep }

/// Default focus padding when neither the step nor the target sets one.
const double kHintFocusPadding = 4.0;

/// Step/slot copy: strings and/or localized builders — one place for the
/// zero-config ↔ l10n precedence (builders win), shared by [HintStep],
/// [HintTooltip] and `DefaultTooltip`.
@immutable
class HintStepContent {
  const HintStepContent({
    this.title,
    this.description,
    this.titleBuilder,
    this.descriptionBuilder,
  });

  /// Zero-config title/description; ignored when a `tooltipBuilder` is set.
  final String? title;
  final String? description;

  /// Localized builders; called with the overlay's BuildContext at show
  /// time. Takes precedence over [title]/[description] — use for l10n:
  /// `titleBuilder: (c) => AppLocalizations.of(c)!.introTitle`.
  final String Function(BuildContext)? titleBuilder;
  final String Function(BuildContext)? descriptionBuilder;

  bool get isEmpty =>
      title == null &&
      description == null &&
      titleBuilder == null &&
      descriptionBuilder == null;

  /// Effective title for [context] — builders take precedence.
  String? effectiveTitle(BuildContext context) =>
      titleBuilder?.call(context) ?? title;

  /// Effective description for [context] — builders take precedence.
  String? effectiveDescription(BuildContext context) =>
      descriptionBuilder?.call(context) ?? description;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      };

  factory HintStepContent.fromJson(Map<String, dynamic> json) =>
      HintStepContent(
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
}

/// What a tap on one region (target or overlay) does — one entity instead of
/// a bool + callback pair.
///
/// The machine only ever sees `UserNext`: these behaviors gate or replace
/// that single action for the region (an action is a state change; the
/// region config does not invent a second action pipeline).
@immutable
sealed class HintTapBehavior {
  const HintTapBehavior();

  /// Default: advance the tour (`actions.next()`).
  const factory HintTapBehavior.advance() = HintTapAdvance;

  /// Ignore taps in this region (no advance, no callback).
  const factory HintTapBehavior.ignore() = HintTapIgnore;

  /// Run [onTap] instead of advancing; call `ctx.actions.next()` yourself
  /// when the step should continue. Not serializable (like every callback).
  const factory HintTapBehavior.custom(
    void Function(HintTooltipContext ctx, TapDownDetails details) onTap,
  ) = HintTapCustom;
}

/// Tap in the region advances the tour (the historical default).
///
/// Engine-internal variant — construct through
/// [HintTapBehavior.advance].
@internal
final class HintTapAdvance extends HintTapBehavior {
  const HintTapAdvance();
}

/// Tap in the region is ignored.
///
/// Engine-internal variant — construct through
/// [HintTapBehavior.ignore].
@internal
final class HintTapIgnore extends HintTapBehavior {
  const HintTapIgnore();
}

/// Tap in the region runs a custom handler instead of advancing.
///
/// Engine-internal variant — construct through
/// [HintTapBehavior.custom].
@internal
final class HintTapCustom extends HintTapBehavior {
  const HintTapCustom(this.onTap);

  final void Function(HintTooltipContext ctx, TapDownDetails details) onTap;
}

/// A single tour step — data, not a widget.
///
/// Two content paths: zero-config (`title`/`description` +
/// `titleBuilder`/`descriptionBuilder`, rendered by the default tooltip from
/// [HintTheme]) and custom (`tooltipBuilder`, the full-customization ladder).
/// `tooltipBuilder` is the only widget-typed slot in the contract — a
/// deliberate exception to allow fully replacing a tooltip.
@immutable
class HintStep {
  const HintStep({
    required this.targetId,
    this.moreTargets = const [],
    this.moreTooltips = const [],
    String? title,
    String? description,
    String Function(BuildContext)? titleBuilder,
    String Function(BuildContext)? descriptionBuilder,
    this.position = TooltipPosition.auto,
    this.stepTimeout,
    this.showSkip = true,
    this.missingTargetPolicy,
    this.targetTap = const HintTapBehavior.advance(),
    this.overlayTap = const HintTapBehavior.advance(),
    this.tooltipBuilder,
    this.focusShape,
    this.focusPadding,
    this.autoScroll,
    this.transitionDuration,
    this.transition,
    this.targetRect,
    this.onStepEnter,
    this.onStepExit,
  })  : assert(targetId != '', 'HintStep.targetId must not be empty'),
        assert(
          tooltipBuilder != null ||
              title != null ||
              description != null ||
              titleBuilder != null ||
              descriptionBuilder != null,
          'HintStep must have content (title/description/builders) '
          'or tooltipBuilder (custom tooltip)',
        ),
        _title = title,
        _description = description,
        _titleBuilder = titleBuilder,
        _descriptionBuilder = descriptionBuilder;

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

  final String? _title;
  final String? _description;
  final String Function(BuildContext)? _titleBuilder;
  final String Function(BuildContext)? _descriptionBuilder;

  /// Copy for the primary tooltip (strings + optional l10n builders).
  /// Built from the constructor sugar `title`/`description`/`titleBuilder`/
  /// `descriptionBuilder`.
  HintStepContent get content => HintStepContent(
        title: _title,
        description: _description,
        titleBuilder: _titleBuilder,
        descriptionBuilder: _descriptionBuilder,
      );

  /// Sugar over [content]'s `title` — prefer reading [content] when both
  /// are relevant.
  String? get title => content.title;
  String? get description => content.description;
  String Function(BuildContext)? get titleBuilder => content.titleBuilder;
  String Function(BuildContext)? get descriptionBuilder =>
      content.descriptionBuilder;

  final TooltipPosition position;

  /// Wait-for-target timeout for this step; null — inherits [HintTour.stepTimeout].
  final Duration? stepTimeout;

  /// Whether the default tooltip shows a "Skip" button on this step.
  /// Ignored on the last step of a tour (and on a single-step tour/hint):
  /// the tour is about to end anyway — "Done" does the same, so a "Skip"
  /// next to it would be redundant. Shown on intermediate steps only, and
  /// only when this flag is true.
  final bool showSkip;

  /// Missing-target policy for this step; null — inherits
  /// [HintTour.missingTargetPolicy].
  final HintMissingTargetPolicy? missingTargetPolicy;

  /// Tap on a spotlighted target: one behavior (advance / ignore / custom).
  /// Default advances — the historical `tapOnTarget: true`.
  final HintTapBehavior targetTap;

  /// Tap on the scrim (outside any target): same contract as [targetTap].
  final HintTapBehavior overlayTap;

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
  /// time — delegates to [content] (builders take precedence).
  String? effectiveTitle(BuildContext context) =>
      content.effectiveTitle(context);
  String? effectiveDescription(BuildContext context) =>
      content.effectiveDescription(context);

  /// Entry-animation length for [transition]; null — the preset's own
  /// default (200 ms for [HintEntryAnimation.easeOut], 800 ms for
  /// [HintEntryAnimation.sprung]).
  /// Ignored without a curve.
  final Duration? transitionDuration;

  /// Entry-animation preset, see [HintEntryAnimation] (rung 2 of the animation
  /// ladder); null — no animation. Rung 3 (anything custom) is a
  /// [tooltipBuilder] with its own animation widgets.
  final HintEntryAnimation? transition;
  final Rect? targetRect;

  /// Lifecycle: fires once when this step first becomes active — the start
  /// of a *visit*. Async; hooks run serialized (`onStepExit` of the previous
  /// step completes first). Target vanish/reappear does not re-fire it.
  final Future<void> Function()? onStepEnter;

  /// Lifecycle: fires once when the visit ends — step change, finish, skip
  /// or abort. Async; ordered before the next step's [onStepEnter].
  final Future<void> Function()? onStepExit;

  /// All target ids of the step: the primary [targetId] + [moreTargets].
  List<String> get targetIds => [targetId, ...moreTargets];

  bool get hasRectTarget => targetRect != null;

  /// The step's timeout, honoring inheritance.
  Duration resolveTimeout(Duration fallback) => stepTimeout ?? fallback;

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
        if (content.title != null) 'title': content.title,
        if (content.description != null) 'description': content.description,
        'position': position.name,
        if (stepTimeout != null) 'waitTimeoutMs': stepTimeout!.inMilliseconds,
        'showSkip': showSkip,
        if (missingTargetPolicy != null)
          'missingTargetPolicy': missingTargetPolicy!.name,
        // Wire keeps the historical bool: false ⇔ ignore, true ⇔ advance.
        // custom() is code-side only (same as every callback).
        'tapOnTarget': targetTap is! HintTapIgnore,
        'tapOnOverlay': overlayTap is! HintTapIgnore,
        if (focusShape != null) 'focusShape': focusShape!.name,
        if (focusPadding != null) 'focusPadding': focusPadding,
        if (autoScroll != null) 'autoScroll': autoScroll,
        if (transitionDuration != null)
          'transitionDurationMs': transitionDuration!.inMilliseconds,
        if (transition != null) 'transitionCurve': transition!.name,
        if (targetRect != null)
          'targetRect': {
            'left': targetRect!.left,
            'top': targetRect!.top,
            'width': targetRect!.width,
            'height': targetRect!.height
          },
      };

  /// Parses a step payload.
  ///
  /// Throws [FormatException] when `targetId` is missing or empty — treat
  /// the payload as untrusted and keep a bundled fallback tour.
  factory HintStep.fromJson(
    Map<String, dynamic> json, {
    void Function(String warning)? onWarning,
  }) {
    final targetId = json['targetId'];
    if (targetId is! String || targetId.isEmpty) {
      throw const FormatException(
        "hintful: step JSON is missing a non-empty 'targetId'",
      );
    }
    return HintStep(
      targetId: targetId,
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
      position: _enumOrDefault(
          TooltipPosition.values, json['position'], TooltipPosition.auto,
          field: 'position', onWarning: onWarning),
      stepTimeout: json['waitTimeoutMs'] == null
          ? null
          : Duration(milliseconds: json['waitTimeoutMs'] as int),
      showSkip: json['showSkip'] as bool? ?? true,
      missingTargetPolicy: _enumOrNull(
          HintMissingTargetPolicy.values, json['missingTargetPolicy'],
          field: 'missingTargetPolicy', onWarning: onWarning),
      targetTap: (json['tapOnTarget'] as bool? ?? true)
          ? const HintTapBehavior.advance()
          : const HintTapBehavior.ignore(),
      overlayTap: (json['tapOnOverlay'] as bool? ?? true)
          ? const HintTapBehavior.advance()
          : const HintTapBehavior.ignore(),
      focusShape: _enumOrNull(FocusShape.values, json['focusShape'],
          field: 'focusShape', onWarning: onWarning),
      focusPadding: (json['focusPadding'] as num?)?.toDouble(),
      autoScroll: json['autoScroll'] as bool?,
      transitionDuration: json['transitionDurationMs'] == null
          ? null
          : Duration(milliseconds: json['transitionDurationMs'] as int),
      transition: _enumOrNull(
          HintEntryAnimation.values, json['transitionCurve'],
          field: 'transitionCurve', onWarning: onWarning),
      targetRect: json['targetRect'] == null
          ? null
          : Rect.fromLTWH(
              (json['targetRect']['left'] as num).toDouble(),
              (json['targetRect']['top'] as num).toDouble(),
              (json['targetRect']['width'] as num).toDouble(),
              (json['targetRect']['height'] as num).toDouble()),
    );
  }
}

/// An additional tooltip of a step (multi-content): a slot with its own
/// preferred side and content, placed around the primary target alongside the
/// primary tooltip. Informational by default — no action buttons (the primary
/// tooltip owns the tour controls); use [tooltipBuilder] for an interactive
/// slot (it receives the same context as the primary's builder).
@immutable
class HintTooltip {
  const HintTooltip({
    this.position = TooltipPosition.auto,
    String? title,
    String? description,
    String Function(BuildContext)? titleBuilder,
    String Function(BuildContext)? descriptionBuilder,
    this.tooltipBuilder,
  })  : assert(
          tooltipBuilder != null ||
              title != null ||
              description != null ||
              titleBuilder != null ||
              descriptionBuilder != null,
          'HintTooltip must have content (title/description/builders) '
          'or tooltipBuilder (custom tooltip)',
        ),
        _title = title,
        _description = description,
        _titleBuilder = titleBuilder,
        _descriptionBuilder = descriptionBuilder;

  /// Preferred side relative to the primary target. An explicit side is
  /// recommended — auto re-picks by free space and may fight the primary
  /// for the same side. Mirroring still applies when the side does not fit
  /// (and the engine guarantees slots never overlap each other).
  final TooltipPosition position;

  final String? _title;
  final String? _description;
  final String Function(BuildContext)? _titleBuilder;
  final String Function(BuildContext)? _descriptionBuilder;

  /// Copy for this slot — same contract as [HintStep.content].
  HintStepContent get content => HintStepContent(
        title: _title,
        description: _description,
        titleBuilder: _titleBuilder,
        descriptionBuilder: _descriptionBuilder,
      );

  String? get title => content.title;
  String? get description => content.description;
  String Function(BuildContext)? get titleBuilder => content.titleBuilder;
  String Function(BuildContext)? get descriptionBuilder =>
      content.descriptionBuilder;

  String? effectiveTitle(BuildContext context) =>
      content.effectiveTitle(context);
  String? effectiveDescription(BuildContext context) =>
      content.effectiveDescription(context);

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
        position: _enumOrDefault(
            TooltipPosition.values, json['position'], TooltipPosition.auto,
            field: 'position', onWarning: onWarning),
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
    this.minShowVersion,
  })  : assert(id != '', 'HintTour.id must not be empty'),
        assert(steps.length > 0, 'HintTour.steps must not be empty');

  final String id;
  final List<HintStep> steps;

  /// Default wait-for-target timeout for all steps of the tour.
  final Duration stepTimeout;

  /// When set, the tour is gated by [HintStore.shouldShow] against this
  /// version: it shows only if it was never shown or last shown before
  /// `minShowVersion`. Read by [HintController.startOnce] and
  /// `showHintTourOffer` — the one place to declare "targets version X".
  final String? minShowVersion;

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
    String? minShowVersion,
  }) {
    return HintTour(
      id: id,
      steps: [for (final value in values) stepFor(value)],
      stepTimeout: stepTimeout,
      disableBackButton: disableBackButton,
      missingTargetPolicy: missingTargetPolicy,
      autoScroll: autoScroll,
      minShowVersion: minShowVersion,
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
        if (minShowVersion != null) 'minShowVersion': minShowVersion,
      };

  /// Parses a tour payload.
  ///
  /// Throws [FormatException] when the payload is structurally invalid
  /// (missing/empty `id`, `steps`, or a step's `targetId`) — keep a bundled
  /// fallback tour for that case. Unknown enum names fall back to their
  /// defaults (reported through [onWarning]).
  factory HintTour.fromJson(
    Map<String, dynamic> json, {
    void Function(String warning)? onWarning,
  }) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
          "hintful: tour JSON is missing a non-empty 'id'");
    }
    final rawSteps = json['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      throw FormatException(
        "hintful: tour '$id' has no steps — 'steps' must be a non-empty list",
      );
    }
    return HintTour(
      id: id,
      steps: rawSteps
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
      minShowVersion: json['minShowVersion'] as String?,
    );
  }
}

/// Same tour with a different [steps] list — every other field is preserved
/// (typo filtering must not drop tour-level settings such as
/// [HintTour.autoScroll]).
///
/// Internal helper for the controller's release-path typo filter; not part
/// of the public barrel contract.
HintTour hintTourWithSteps(HintTour tour, List<HintStep> steps) => HintTour(
      id: tour.id,
      steps: steps,
      stepTimeout: tour.stepTimeout,
      disableBackButton: tour.disableBackButton,
      missingTargetPolicy: tour.missingTargetPolicy,
      autoScroll: tour.autoScroll,
      minShowVersion: tour.minShowVersion,
    );

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
