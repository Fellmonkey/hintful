import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
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
  /// **No-op contract:** the default body is intentionally empty — it is a
  /// no-op (1) on the first step of a tour and (2) for implementations that
  /// do not expose back-navigation. Calling `previous()` is always safe and
  /// never throws; `HintController` dispatches the real move.
  void previous() {}

  /// Jump to the 0-based [index] of the tour (out of range: a debug assert,
  /// a no-op in release). This is what makes page-indicator dots clickable
  /// in a custom tooltip — without it the dots could only be rendered, not
  /// driven.
  void goTo(int index);

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
///
/// Frozen shape for 1.x: anything added later arrives as an optional
/// named argument or a getter with a default, so both `const`
/// construction and pattern-matching on the existing three stay valid.
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

  /// The whole tour is this one step: a lone hint keeps no action row at
  /// all (no Done next to a Skip that does the same). Every tooltip —
  /// default or custom — needs this decision; without the getter each one
  /// re-derives `totalSteps <= 1`.
  bool get isSingle => totalSteps <= 1;
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
/// Engine-internal - not part of the public barrel (referenced only by
/// engine docs and resolvers).
const double kHintFocusPadding = 4.0;

/// Default corner radius of a [FocusShape.roundedRect] hole when the theme
/// does not set `HintTheme.holeRadius`. Engine-internal, same as
/// [kHintFocusPadding] - the public knob is the theme field.
const double kHintHoleRadius = 12.0;

/// Step/slot copy: strings and/or localized builders — one place for the
/// zero-config ↔ l10n precedence (builders win), shared by [HintStep],
/// [HintAdditionalTooltip] and `DefaultTooltip`.
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

  /// Zero-config title; not rendered by the engine when a `tooltipBuilder`
  /// is set — your builder may still show it (call back into
  /// `DefaultTooltip(step:, ctx:)`, which renders this content).
  final String? title;

  /// Zero-config description; same rendering contract as [title].
  final String? description;

  /// Localized builders; called with the overlay's BuildContext at show
  /// time. Takes precedence over [title]/[description] — use for l10n:
  /// `titleBuilder: (c) => AppLocalizations.of(c)!.introTitle`.
  final String Function(BuildContext)? titleBuilder;

  /// Localized description builder; takes precedence over [description]
  /// (same contract as [titleBuilder]).
  final String Function(BuildContext)? descriptionBuilder;

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
        title: _stringOrNull(json['title'], 'title'),
        description: _stringOrNull(json['description'], 'description'),
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
/// One of the three concrete [HintTapBehavior] variants — construct through
/// [HintTapBehavior.advance]; the subtype is exported so a `switch` over a
/// `sealed` family is exhaustive.
final class HintTapAdvance extends HintTapBehavior {
  /// The default behavior.
  const HintTapAdvance();
}

/// Tap in the region is ignored.
///
/// One of the three concrete [HintTapBehavior] variants - construct through
/// [HintTapBehavior.ignore].
final class HintTapIgnore extends HintTapBehavior {
  /// No advance, no callback.
  const HintTapIgnore();
}

/// Tap in the region runs a custom handler instead of advancing.
///
/// One of the three concrete [HintTapBehavior] variants - construct through
/// [HintTapBehavior.custom].
final class HintTapCustom extends HintTapBehavior {
  /// Binds [onTap] as the region's handler.
  const HintTapCustom(this.onTap);

  /// Runs instead of advancing; the handler calls `ctx.actions.next()` itself
  /// when the step should continue.
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
  /// tooltip renders an empty bubble). Enforced neither by an assert (a
  /// property access is not a potentially-constant expression in a `const`
  /// constructor) nor by diagnostics ([HintSkipReason] is closed in 1.x and
  /// deliberately has no `invalidContent` case) — the rule lives here, in
  /// the docs, and nowhere else.
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
  final List<HintAdditionalTooltip> additionalTooltips;

  /// Preferred side for the primary tooltip — see [TooltipPosition].
  final TooltipPosition position;

  /// Wait-for-target timeout for this step; null — inherits [HintTour.stepTimeout].
  ///
  /// Wire key: `stepTimeoutMs`, the same name the tour's default uses
  /// (the pre-1.0 `waitTimeoutMs` is still accepted when reading).
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
  ///
  /// Builds a fresh list on each access — deliberately not cached: a cached
  /// list would need a lazy (non-`const`) field, costing [HintStep] its
  /// `const` constructor. Every caller is event-driven (a start, a step
  /// change, a target registration/removal), never per frame, so the small
  /// allocation is not worth that trade.
  List<String> get targetIds => [targetId, ...additionalTargets];

  /// Serializes the step to the frozen JSON wire format (see `fromJson`).
  ///
  /// Two deliberate divergences from the Dart names, both fixed by the 1.x
  /// wire: `stepTimeout` → `stepTimeoutMs` and `targetTap`/`overlayTap` →
  /// `tapOnTarget`/`tapOnOverlay`. The tap bools lose their handler:
  /// [HintTapBehavior.custom] serializes as `true` and parses back as
  /// [HintTapBehavior.advance] — callbacks are code-side, so a custom
  /// handler must be re-applied in code after a round-trip. The always /
  /// only-when-non-default split mirrors [HintTour.toJson]'s.
  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        if (additionalTargets.isNotEmpty)
          'additionalTargets': additionalTargets,
        if (additionalTooltips.isNotEmpty)
          'additionalTooltips':
              additionalTooltips.map((t) => t.toJson()).toList(),
        ...content.toJson(),
        'position': position.name,
        if (stepTimeout != null) 'stepTimeoutMs': stepTimeout!.inMilliseconds,
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
  /// Throws [FormatException] when the payload is untrusted: a missing or
  /// empty `targetId`, or any field of the wrong type.
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
    // The single most plausible producer mistake is mirroring the Dart API:
    // {"targetId": …, "content": {"title": …}} would otherwise parse into an
    // empty bubble with no diagnosis at all.
    if (json.containsKey('content')) {
      _warn(
        "hintful: step JSON key 'content' is not part of the wire format —"
        " the wire is flat ('title'/'description' at the step level)",
        onWarning,
      );
    }
    return HintStep(
      targetId: targetId,
      content: HintStepContent.fromJson(json),
      additionalTargets:
          _stringListOrNull(json['additionalTargets'], 'additionalTargets') ??
              const [],
      additionalTooltips:
          _listOrNull(json['additionalTooltips'], 'additionalTooltips')
                  ?.map((e) => HintAdditionalTooltip.fromJson(
                        _mapField(e, 'additionalTooltips'),
                        onWarning: onWarning,
                      ))
                  .toList() ??
              const [],
      position: _enumOrDefault(
          TooltipPosition.values, json['position'], TooltipPosition.auto,
          field: 'position', onWarning: onWarning),
      stepTimeout: _stepTimeoutFromJson(json),
      showSkip: _boolOrNull(json['showSkip'], 'showSkip') ?? true,
      targetTap: (_boolOrNull(json['tapOnTarget'], 'tapOnTarget') ?? true)
          ? const HintTapBehavior.advance()
          : const HintTapBehavior.ignore(),
      overlayTap: (_boolOrNull(json['tapOnOverlay'], 'tapOnOverlay') ?? true)
          ? const HintTapBehavior.advance()
          : const HintTapBehavior.ignore(),
      focusShape: _enumOrNull(FocusShape.values, json['focusShape'],
          field: 'focusShape', onWarning: onWarning),
      focusPadding: _doubleOrNull(json['focusPadding'], 'focusPadding'),
      autoScroll: _boolOrNull(json['autoScroll'], 'autoScroll'),
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
class HintAdditionalTooltip {
  /// Creates a slot with [content] or a [tooltipBuilder], on its own
  /// [position] around the primary target. Empty content with no builder
  /// renders nothing useful — same authoring rule (and the same
  /// not-asserted rationale) as [HintStep].
  const HintAdditionalTooltip({
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
        ...content.toJson(),
      };

  /// Parses a slot payload; an unknown `position` falls back to
  /// [TooltipPosition.auto] (reported through [onWarning]).
  factory HintAdditionalTooltip.fromJson(
    Map<String, dynamic> json, {
    void Function(String warning)? onWarning,
  }) =>
      HintAdditionalTooltip(
        position: _enumOrDefault(
            TooltipPosition.values, json['position'], TooltipPosition.auto,
            field: 'position', onWarning: onWarning),
        content: HintStepContent.fromJson(json),
      );
}

/// Default wait-for-target timeout for a step when neither the step nor the
/// tour sets one — the single source for [HintTour.stepTimeout]'s constructor
/// default and for the JSON default of `stepTimeoutMs`.
const Duration _kDefaultStepTimeout = Duration(seconds: 3);

/// A hint tour — a declarative sequence of [HintStep]s.
///
/// Pure data, serializable 1-to-1 to JSON (server-driven tours via
/// `fromJson`): `{id, steps: [{targetId, title, ...}], stepTimeoutMs}`.
///
/// ## Where each knob lives
///
/// The knobs are not uniformly inheritable — this is the whole model, so
/// you never have to guess which tier a setting belongs to:
///
/// | knob | on `HintTarget` | on `HintTour` | on `HintStep` |
/// |---|---|---|---|
/// | `focusShape` / `focusPadding` | ✓ | – | ✓ (overrides the target) |
/// | `autoScroll` | – | ✓ (default) | ✓ (overrides the tour) |
/// | `stepTimeout` | – | ✓ (default) | ✓ (overrides the tour) |
/// | `position` | – | – | ✓ (plus one per extra tooltip) |
/// | `showSkip` | – | – | ✓ |
/// | `targetTap` / `overlayTap` | – | – | ✓ |
/// | `missingTargetPolicy` | – | ✓ | – (tour-wide by design) |
/// | `disableBackButton` | – | ✓ | – |
/// | `minShowVersion` | – | ✓ | – |
/// | `onStepEnter` / `onStepExit` | – | – | ✓ |
///
/// Only `focusShape`/`focusPadding` are set on the widget — everything else
/// is tour data, so a tour stays serializable and a target stays reusable
/// across tours.
@immutable
class HintTour {
  /// Creates a tour of [steps] under a non-empty [id].
  const HintTour({
    required this.id,
    required this.steps,
    this.stepTimeout = _kDefaultStepTimeout,
    this.disableBackButton = false,
    this.missingTargetPolicy = HintMissingTargetPolicy.skipStep,
    this.autoScroll = false,
    this.minShowVersion,
    this.onExited,
  })  : assert(id != '', 'HintTour.id must not be empty'),
        assert(steps.length > 0, 'HintTour.steps must not be empty');

  /// Stable tour id — non-empty; diagnostics, stores and offers key on it.
  final String id;

  /// Ordered steps of the tour; must be non-empty.
  final List<HintStep> steps;

  /// Default wait-for-target timeout for all steps of the tour.
  final Duration stepTimeout;

  /// When set, the guarded entry points show this tour only if it was never
  /// shown or was last shown before `minShowVersion`: [HintController
  /// .tryShowTour] (which `showHint` and `showHintTourOffer` go through)
  /// checks it on every call and records the result with
  /// [HintMarkPolicy.onAnyExit] when no `mark:` was given — so declaring the
  /// floor is enough, no second knob.
  ///
  /// [HintController.showTour] is deliberately NOT gated: it is the loud,
  /// assert-based path ("show this now"), and a silent store no-op there
  /// would contradict it.
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

  /// Fires once when the tour leaves the screen — the tour-level half of the
  /// per-step [HintStep.onStepEnter]/[HintStep.onStepExit] pair, and the
  /// only way to tell "finished" from "abandoned" without bookkeeping: the
  /// observable state before the tour and after it are both [HintIdle].
  ///
  /// `finished` is `true` when the tour ran to the end (Done / last step)
  /// and `false` when it was skipped, aborted or timed out. Async; runs
  /// through the same serialized hook queue as the step hooks, after the
  /// last step's `onStepExit`. Not serializable (like every callback).
  final Future<void> Function(bool finished)? onExited;

  /// Target ids referenced by more than one step — a tour-authoring error
  /// (one tour at a time, a duplicated target is ambiguous). Counts
  /// [HintStep.targetIds] (extras included); repeating an id WITHIN one step
  /// is not a duplicate (the same hole twice is harmless). The check is
  /// cheap and lazy; used by the controller's showTour validation.
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
  ///
  /// **What is written:** the identity and structural fields always (`id`,
  /// `steps`, `stepTimeoutMs`, `disableBackButton`, `missingTargetPolicy`);
  /// the optional behaviour flags only when they differ from their Dart
  /// default (`autoScroll`, `minShowVersion`); callbacks (`onStepEnter`,
  /// `onStepExit`, `onExited`, `tooltipBuilder`) never — they are code-side
  /// only. `fromJson` applies the same defaults on read, so an
  /// under-specified payload round-trips to the same tour.
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
  /// Throws [FormatException] when the payload is untrusted: missing/empty
  /// `id`, `steps`, or a step's `targetId`, or any field of the wrong type —
  /// keep a bundled fallback tour for that case. Unknown enum names fall back
  /// to their defaults (reported through [onWarning]).
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
                _mapField(step, 'steps'),
                onWarning: onWarning,
              ))
          .toList(),
      stepTimeout: json['stepTimeoutMs'] == null
          ? _kDefaultStepTimeout
          : Duration(
              milliseconds:
                  _intOrNull(json['stepTimeoutMs'], 'stepTimeoutMs')!),
      disableBackButton:
          _boolOrNull(json['disableBackButton'], 'disableBackButton') ?? false,
      autoScroll: _boolOrNull(json['autoScroll'], 'autoScroll') ?? false,
      missingTargetPolicy: _enumOrDefault(HintMissingTargetPolicy.values,
          json['missingTargetPolicy'], HintMissingTargetPolicy.skipStep,
          field: 'missingTargetPolicy', onWarning: onWarning),
      minShowVersion: _stringOrNull(json['minShowVersion'], 'minShowVersion'),
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
      onExited: tour.onExited,
    );

/// Reports a non-fatal wire problem: `debugPrint` in debug builds, plus the
/// optional `onWarning` the `fromJson` entry points thread down.
void _warn(String warning, void Function(String warning)? onWarning) {
  if (kDebugMode) debugPrint(warning);
  onWarning?.call(warning);
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
  _warn("hintful: unknown $field '$name' — using the default", onWarning);
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

// ─────────────── untrusted-payload coercions (no raw casts) ───────────────

// The documented recovery from a bad server-driven tour is
// `on FormatException catch` + a bundled fallback — so every `fromJson` field
// goes through these helpers, never a raw `as`: a wrong-typed value must
// throw FormatException AT PARSE TIME (a TypeError escapes that catch, and a
// lazy cast defers it to the first read), and it must not be silently
// coerced, which would hide producer bugs. New field → add a helper or reuse
// one; keep the rule stated here, not in each helper.

Never _badType(String field, Object? value) => throw FormatException(
      "hintful: field '$field' has an unexpected type"
      ' (${value.runtimeType})',
    );

/// JSON string or null (absent field).
String? _stringOrNull(Object? value, String field) =>
    value is String? ? value : _badType(field, value);

/// JSON int or null (absent field).
int? _intOrNull(Object? value, String field) =>
    value is int? ? value : _badType(field, value);

/// JSON bool or null (absent field).
bool? _boolOrNull(Object? value, String field) =>
    value is bool? ? value : _badType(field, value);

/// JSON number (int or double) or null (absent field), as a double.
double? _doubleOrNull(Object? value, String field) =>
    value is num? ? value?.toDouble() : _badType(field, value);

/// A JSON list or null (absent field). Elements are validated where they are
/// consumed.
List? _listOrNull(Object? value, String field) =>
    value is List? ? value : _badType(field, value);

/// A JSON object (string-keyed map), or [FormatException] at parse time.
Map<String, dynamic> _mapField(Object? value, String field) =>
    value is Map<String, dynamic> ? value : _badType(field, value);

/// A JSON list of strings, validated element-by-element at parse time —
/// null (absent field) → null.
List<String>? _stringListOrNull(Object? value, String field) {
  if (value == null) return null;
  if (value is! List) _badType(field, value);
  return [
    for (final element in value)
      element is String ? element : _badType(field, element),
  ];
}

/// Step wait-for-target timeout from the wire.
///
/// Reads `stepTimeoutMs` — symmetric with the tour default's key, so a step
/// written as `{"stepTimeoutMs": …}` is not silently ignored — and falls back
/// to the pre-1.0 `waitTimeoutMs`. The canonical name wins when both appear.
Duration? _stepTimeoutFromJson(Map<String, dynamic> json) {
  for (final field in const ['stepTimeoutMs', 'waitTimeoutMs']) {
    final value = json[field];
    if (value != null) {
      return Duration(milliseconds: _intOrNull(value, field)!);
    }
  }
  return null;
}
