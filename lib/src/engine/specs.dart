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
enum TooltipPosition {
  /// Pick the side with the most free space, re-evaluated live (the default).
  auto,

  /// Above the target.
  top,

  /// Below the target.
  bottom,

  /// Left of the target.
  left,

  /// Right of the target.
  right,
}

/// Hole shape cut into the scrim around a spotlighted target.
///
/// Closed in 1.x: no new values before 2.0 — exhaustive `switch`es in app
/// code are safe.
enum FocusShape {
  /// Sharp-cornered rectangle (the default).
  rectangle,

  /// Circle inscribed in the target bounds.
  circle,

  /// Rectangle with rounded corners.
  roundedRect,
}

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

  /// Go one step back.
  ///
  /// **No-op contract:** the default body is intentionally empty. It is a
  /// no-op (1) on the first step of a tour, and (2) for custom tooltips /
  /// [HintActions] implementations that do not expose back-navigation —
  /// calling `previous()` is always safe and never throws. Override only
  /// when the surface actually moves backward (`HintController` dispatches
  /// `UserPrevious`); forgetting to override is a silent no-op, not a bug
  /// in the caller's code.
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
  /// Builds a context bound to [actions] and a position within the tour.
  const HintTooltipContext({
    required this.actions,
    required this.stepIndex,
    required this.totalSteps,
  });

  /// Tour actions the tooltip can invoke (next/skip/previous/finish).
  final HintActions actions;

  /// 0-based index of the step this context describes.
  final int stepIndex;

  /// Total number of steps in the tour.
  final int totalSteps;

  /// Last step of the tour: Next becomes Done.
  bool get isLast => stepIndex == totalSteps - 1;
}

/// What to do when a step's target never appears within its wait timeout.
///
/// - [skipStep] (default) — the step is diagnosed and the tour continues with
///   the next one; skipping the last step finishes the tour. For
///   conditionally-absent targets pair with a short per-step `stepTimeout`
///   (`Duration.zero` skips instantly, no waiting flash).
/// - [abortTour] — the tour ends with a `timeout` diagnosis.
///
/// Closed in 1.x: no new values before 2.0 — exhaustive `switch`es in app
/// code are safe.
enum HintMissingTargetPolicy {
  /// The tour ends with a `timeout` diagnosis.
  abortTour,

  /// The step is diagnosed and the tour continues with the next step
  /// (the default).
  skipStep,
}

/// Default focus padding when neither the step nor the target sets one.
/// Engine-internal — not part of the public barrel (referenced only by
/// engine docs and resolvers).
const double kHintFocusPadding = 4.0;

/// Step/slot copy: strings and/or localized builders — one place for the
/// zero-config ↔ l10n precedence (builders win), shared by [HintStep],
/// [HintTooltip] and `DefaultTooltip`.
@immutable
class HintStepContent {
  /// Copy for a step/slot: strings and/or localized builders (all optional —
  /// an empty content renders nothing).
  const HintStepContent({
    this.title,
    this.description,
    this.titleBuilder,
    this.descriptionBuilder,
  });

  /// Zero-config title/description; ignored when a `tooltipBuilder` is set.
  final String? title;

  /// Zero-config description; ignored when a `tooltipBuilder` is set.
  final String? description;

  /// Localized builders; called with the overlay's BuildContext at show
  /// time. Takes precedence over [title]/[description] — use for l10n:
  /// `titleBuilder: (c) => AppLocalizations.of(c)!.introTitle`.
  final String Function(BuildContext)? titleBuilder;

  /// Localized description builder; takes precedence over [description]
  /// (same contract as [titleBuilder]).
  final String Function(BuildContext)? descriptionBuilder;

  /// No strings and no builders — the slot renders nothing.
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

  /// Serializes the string copy (builders are code-side only).
  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      };

  /// Parses the string copy from JSON (builders are code-side only).
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
/// Two content paths: zero-config ([content] — strings and/or l10n builders,
/// rendered by the default tooltip from [HintTheme]) and custom
/// (`tooltipBuilder`, the full-customization ladder). `tooltipBuilder` is the
/// only widget-typed slot in the contract — a deliberate exception to allow
/// fully replacing a tooltip.
@immutable
class HintStep {
  /// Creates a step: non-empty [targetId], and [content] or a
  /// [tooltipBuilder] (authoring rule — empty content with no custom
  /// tooltip renders nothing useful, but is not asserted: property access
  /// is not a potentially-constant expression in a const constructor).
  const HintStep({
    required this.targetId,
    this.content = const HintStepContent(),
    this.additionalTargets = const [],
    this.additionalTooltips = const [],
    this.position = TooltipPosition.auto,
    this.stepTimeout,
    this.showSkip = true,
    this.targetTap = const HintTapBehavior.advance(),
    this.overlayTap = const HintTapBehavior.advance(),
    this.tooltipBuilder,
    this.focusShape,
    this.focusPadding,
    this.autoScroll,
    this.onStepEnter,
    this.onStepExit,
  }) : assert(targetId != '', 'HintStep.targetId must not be empty');

  /// Key in the target registry — not a GlobalKey.
  final String targetId;

  /// Copy for the primary tooltip (strings + optional l10n builders).
  final HintStepContent content;

  /// Additional targets spotlighted together with [targetId] (multi-target
  /// step: several elements highlighted at once, one tooltip anchored to the
  /// primary [targetId]). The step enters the active phase only when ALL of
  /// [targetIds] are mounted; a scrim hole is cut over each of them.
  final List<String> additionalTargets;

  /// Additional tooltips (multi-content): placed around the primary
  /// target alongside the primary tooltip, each on its own side. The engine
  /// guarantees they do not overlap each other or the spotlighted targets
  /// (keep-in-safe-area applies to every slot).
  final List<HintTooltip> additionalTooltips;

  /// Preferred side for the primary tooltip — see [TooltipPosition].
  final TooltipPosition position;

  /// Wait-for-target timeout for this step; null — inherits [HintTour.stepTimeout].
  final Duration? stepTimeout;

  /// Whether the default tooltip shows a "Skip" button on this step.
  /// Ignored on the last step of a tour (and on a single-step tour/hint):
  /// the tour is about to end anyway — "Done" does the same, so a "Skip"
  /// next to it would be redundant. Shown on intermediate steps only, and
  /// only when this flag is true.
  final bool showSkip;

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

  /// Spotlight padding for this step; null — inherits from [HintTarget]
  /// or the internal default (4.0 logical px).
  final double? focusPadding;

  /// Auto-scroll the primary target into view when the step activates.
  /// null — inherits from [HintTour.autoScroll]; `false` by default —
  /// the engine never moves content unless you opt in.
  final bool? autoScroll;

  /// Lifecycle: fires once when this step first becomes active — the start
  /// of a *visit*. Async; hooks run serialized (`onStepExit` of the previous
  /// step completes first). Target vanish/reappear does not re-fire it.
  final Future<void> Function()? onStepEnter;

  /// Lifecycle: fires once when the visit ends — step change, finish, skip
  /// or abort. Async; ordered before the next step's [onStepEnter].
  final Future<void> Function()? onStepExit;

  /// All target ids of the step: the primary [targetId] +
  /// [additionalTargets].
  List<String> get targetIds => [targetId, ...additionalTargets];

  /// Serializes the step to the frozen JSON wire format (see `fromJson`).
  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        if (additionalTargets.isNotEmpty)
          'additionalTargets': additionalTargets,
        if (additionalTooltips.isNotEmpty)
          'additionalTooltips':
              additionalTooltips.map((t) => t.toJson()).toList(),
        if (content.title != null) 'title': content.title,
        if (content.description != null) 'description': content.description,
        'position': position.name,
        if (stepTimeout != null) 'waitTimeoutMs': stepTimeout!.inMilliseconds,
        'showSkip': showSkip,
        // Wire keeps the historical bool: false ⇔ ignore, true ⇔ advance.
        // custom() is code-side only (same as every callback).
        'tapOnTarget': targetTap is! HintTapIgnore,
        'tapOnOverlay': overlayTap is! HintTapIgnore,
        if (focusShape != null) 'focusShape': focusShape!.name,
        if (focusPadding != null) 'focusPadding': focusPadding,
        if (autoScroll != null) 'autoScroll': autoScroll,
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
      content: HintStepContent(
        title: json['title'] as String?,
        description: json['description'] as String?,
      ),
      additionalTargets:
          (json['additionalTargets'] as List?)?.cast<String>() ?? const [],
      additionalTooltips: (json['additionalTooltips'] as List?)
              ?.map((e) => HintTooltip.fromJson(
                    e as Map<String, dynamic>,
                    onWarning: onWarning,
                  ))
              .toList() ??
          const [],
      position: _enumOrDefault(
          TooltipPosition.values, json['position'], TooltipPosition.auto,
          field: 'position', onWarning: onWarning),
      stepTimeout: json['waitTimeoutMs'] == null
          ? null
          : Duration(milliseconds: json['waitTimeoutMs'] as int),
      showSkip: json['showSkip'] as bool? ?? true,
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
    );
  }
}

/// An additional tooltip of a step (multi-content): a slot with its own
/// preferred side and content, placed around the primary target alongside the
/// primary tooltip. Informational by default — no action buttons (the primary
/// tooltip owns the tour controls); use [tooltipBuilder] for an interactive
/// slot (it receives the same context as the primary's builder).
///
/// The content slot is the same [HintStepContent] type [HintStep] takes —
/// one authoring shape for every content slot in the contract.
@immutable
class HintTooltip {
  /// Creates a slot with [content] or a [tooltipBuilder], on its own
  /// [position] around the primary target. Empty content with no builder
  /// renders nothing useful — same authoring rule (and the same
  /// not-asserted rationale) as [HintStep].
  const HintTooltip({
    this.position = TooltipPosition.auto,
    this.content = const HintStepContent(),
    this.tooltipBuilder,
  });

  /// Preferred side relative to the primary target. An explicit side is
  /// recommended — auto re-picks by free space and may fight the primary
  /// for the same side. Mirroring still applies when the side does not fit
  /// (and the engine guarantees slots never overlap each other).
  final TooltipPosition position;

  /// Copy for this slot — same contract as [HintStep.content].
  final HintStepContent content;

  /// Fully custom content.
  final Widget Function(
    BuildContext context,
    HintStep step,
    HintTooltipContext ctx,
  )? tooltipBuilder;

  /// Serializes the slot to the frozen JSON wire format (position + string
  /// copy; builders are code-side only).
  Map<String, dynamic> toJson() => {
        'position': position.name,
        if (content.title != null) 'title': content.title,
        if (content.description != null) 'description': content.description,
      };

  /// Parses a slot payload; an unknown `position` falls back to
  /// [TooltipPosition.auto] (reported through [onWarning]).
  factory HintTooltip.fromJson(
    Map<String, dynamic> json, {
    void Function(String warning)? onWarning,
  }) =>
      HintTooltip(
        position: _enumOrDefault(
            TooltipPosition.values, json['position'], TooltipPosition.auto,
            field: 'position', onWarning: onWarning),
        content: HintStepContent.fromJson(json),
      );
}

/// A hint tour — a declarative sequence of [HintStep]s.
///
/// Pure data, serializable 1-to-1 to JSON (server-driven tours via
/// `fromJson`): `{id, steps: [{targetId, title, ...}], stepTimeout}`.
@immutable
class HintTour {
  /// Creates a tour of [steps] under a non-empty [id].
  const HintTour({
    required this.id,
    required this.steps,
    this.stepTimeout = const Duration(seconds: 3),
    this.disableBackButton = false,
    this.missingTargetPolicy = HintMissingTargetPolicy.skipStep,
    this.autoScroll = false,
    this.minShowVersion,
  })  : assert(id != '', 'HintTour.id must not be empty'),
        assert(steps.length > 0, 'HintTour.steps must not be empty');

  /// Stable tour id — non-empty; diagnostics, stores and offers key on it.
  final String id;

  /// Ordered steps of the tour; must be non-empty.
  final List<HintStep> steps;

  /// Default wait-for-target timeout for all steps of the tour.
  final Duration stepTimeout;

  /// When set, the tour is gated by [HintStore.shouldShow] against this
  /// version: it shows only if it was never shown or last shown before
  /// `minShowVersion`. Read by [HintController.startOnce] and
  /// `showHintTourOffer` — the one place to declare "targets version X".
  final String? minShowVersion;

  /// Default missing-target policy for all steps of the tour: abort the
  /// tour, or show every step whose target exists
  /// ([HintMissingTargetPolicy.skipStep]). Tour-level only — pair with a
  /// short per-step `stepTimeout` (`Duration.zero` skips instantly) for
  /// conditionally-absent targets.
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

  /// Serializes the tour to the frozen JSON wire format (see `fromJson`).
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

/// Inheritance resolution on a [HintStep] — deliberately an extension, not
/// part of the class's public surface: the barrel does not export it, so
/// package consumers cannot call these (the `fallback`/`tourPolicy`
/// arguments are the machine's business, not the app's). Same pattern as
/// the registry's register-path extension; reachable by the engine and the
/// package's own tests through `lib/src`.
extension HintStepInternal on HintStep {
  /// The step's timeout, honoring inheritance.
  Duration resolveTimeout(Duration fallback) => stepTimeout ?? fallback;
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
