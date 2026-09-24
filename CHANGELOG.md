# Changelog

## 1.0.0

### Release-candidate API slimming (the final 1.0 surface)

The nine-point pre-tag slim-down toward the "install and forget" ideal. The
rest of this section is the accumulated dev log — entries below that touch
the same areas describe the final state as amended here.

- **Sugar getters are gone (final):** `HintStep`/`HintTooltip` expose only
  the `content` slot — the `title`/`description`/`titleBuilder`/
  `descriptionBuilder` getters are removed; read `step.content.title` etc.
  (amends the `content:` entries below).
- **Animation is `tooltipBuilder`'s job (final):** `HintEntryAnimation`,
  `HintStep.transition`/`transitionDuration` and the exported
  `hintTransitionDuration` helper are removed — a custom builder animates
  its own entry (honor `MediaQuery.disableAnimations` inline). (Amends the
  preset entries below.)
- **Rect targets are gone (final):** `HintStep.targetRect`, the machine's
  rect branches, the `overlay:` constructor parameter and the
  `HintOverlayProvider` typedef are removed — every step anchors to
  registered `HintTarget`s. (Amends the rect entries below.)
- **Headless is a test seam (final):** `HintController()` always renders.
  Headless runs (tests, pure machines) move to the `@visibleForTesting`
  factory `HintController.test({headless = true, registry, diagnostics,
  scopePrefix, store})`. (Amends the `headless: true` note below.)
- **App-wide store config (final):** the mutable `HintController.store`
  field and `effectiveStore` are gone. Configure once at startup:
  `Hintful.configure(store: ...)` — the new `Hintful` class (exported from
  the barrel); controllers read `Hintful.store`, falling back to a
  session-scoped `InMemoryHintStore` (debug prints a one-time warning).
  (Amends the "No per-call store" entry below.)
- **`HintStore` contract frozen at two members:** `clear()` leaves the
  abstract contract (a concrete store may expose its own dev tool); the
  public `compareVersions` leaves the core. The shipped **`hintful_prefs`
  companion package** (new) provides `SharedPreferencesHintStore`
  (namespaced keys, `clear()`) and a public `compareVersions()`.
- **Defaults changed:** `HintMarkPolicy.onAnyExit` is the default mark
  policy for `startOnce` and `showHintTourOffer` (was `onFinish` — skip
  counts as "seen"); `HintMissingTargetPolicy.skipStep` is the tour default
  (was `abortTour` — a missing target no longer kills the tour).
- **Renames and removals:** `moreTargets` → `additionalTargets`,
  `moreTooltips` → `additionalTooltips` (the JSON wire keys rename with
  them — a coordinated wire change at 1.0); `HintTour.fromEnum` is removed —
  declare the steps list directly (a private helper over your enum works
  the same).

### Engine and contract work (dev log)

- **Offer result is four-valued:** **Breaking** — `HintTourOfferResult`
  splits `declined` into `declined` (the user declined this dialog),
  `alreadyShown` (gate closed: tour ran for this version, or a previous
  decline — no dialog was shown) and `busy` (accept while another tour is
  running — nothing started). Exhaustive `switch`es must handle the new
  values.
- **No per-call store:** **Breaking** — `startOnce(store:)` and
  `showHintTourOffer(store:)` parameters are gone. The store is configured
  app-wide via `Hintful.configure(store: ...)` (see the slimming block
  above); when unset, a session-scoped `InMemoryHintStore` takes over
  (debug prints a one-time warning) — show-once works out of the box, state
  lives for this run only.
- **`HintMarkPolicy` replaces `markOnFinish`:** **Breaking** —
  `startOnce(mark:)` and `showHintTourOffer(mark:)` take a closed
  `HintMarkPolicy`: `onAnyExit` (default — finish, skip or timeout all
  count, the slimming default above; retires the hand-rolled
  idle-listener pattern), `onFinish` (Done/last step only, the old
  `markOnFinish: true`), `manual` (never — the app owns the shown-state;
  the old `markOnFinish: false`).
- **`HintStep` takes `content:`:** **Breaking** — the constructor's
  `title`/`description`/`titleBuilder`/`descriptionBuilder` sugar params
  are gone; pass `content: HintStepContent(...)` (the sugar getters over
  `content` are removed by the slimming block above — read
  `step.content.title` etc.). JSON wire keeps the flat `title`/`description`
  keys.
- **`HintTooltip` takes `content:`:** **Breaking** — the multi-content slot
  drops its flat `title`/`description`/`titleBuilder`/`descriptionBuilder`
  constructor params and matches `HintStep`: pass
  `content: HintStepContent(...)` (sugar getters removed — see the
  slimming block). One content slot type across the contract; JSON wire
  keys are unchanged.
- **Per-step `missingTargetPolicy` is gone:** **Breaking** — the tour-level
  `HintTour.missingTargetPolicy` is the single policy; the step-level field
  and `resolveMissingPolicy` disappear (the wire key is ignored if present).
  Pair conditionally-absent targets with a short per-step `stepTimeout`.
- **Transition presets and rect targets:** both systems were removed by
  the slimming block above — see those entries.
- **`HintTourOfferLabels` gets `copyWith` + `==`/`hashCode`:** matches
  `HintTooltipLabels` (value semantics for theme overrides).
- **Default rendering:** `HintController()` now renders out of the box — the
  default engine wiring runs instead of a headless mode. Migration: headless
  runs (tests, pure machines) use the `@visibleForTesting` factory
  `HintController.test()` (see the slimming block above).
- **Render contract is internal:** **Breaking** — `HintOverlayHost`,
  `defaultOverlayHost`,  `HintPosition`/`PositionedHint`/`UnpositionedHint`/
  `HintPositionResolver` leave the public barrel. The constructor's
  `overlayHostBuilder:` parameter is gone (rect tours are removed — see
  the slimming block); test seams use `@internal HintController.withHost`.
- **Register-path is internal:** **Breaking** — `HintTargetRegistration` and
  `register`/`unregister`/`lookup` leave the barrel (an internal extension).
  Drive targets through `HintTarget`; the public registry exposes
  `defaultInstance`, `onWarning`, `addListener`, `removeListener`, `ids`.
- **Diagnostics as an event object:** **Breaking** —
  `HintDiagnosticsHandler` is now a plain function type
  (`void Function(HintSkipEvent)`) — one callback per controller, passed as
  `diagnostics:`; attach several sinks inside the function. The event carries
  `tourId`, `stepIndex`, `targetId`, `reason`, `detail`; new fields can be
  added in 1.x (optional-only — a new `required` field would break event
  construction). Debug builds **always print** the `[hintful] …` line first,
  then invoke your callback; release runs the callback alone (or nothing).
  `DebugPrintDiagnostics` (class) is gone; `closestTargetIds`,
  `formatHintSkipped`, `debugPrintHintSkip` are internal. `kHintFocusPadding`
  and the internal `hintTourWithSteps` are also out of the barrel.
- **New `CallbackHintStore(read:, write:)`** — the
  three-line persistent store over your storage, no subclass ceremony
  (`onClear` is gone with the contract freeze — concrete stores expose
  their own `clear()`; the `hintful_prefs` store does).
- **Internal helpers leave the public class surface:** `HintStep.resolveTimeout` /
  `hasRectTarget` and `HintController.inScope` move
  to unexported extensions (same pattern as the register-path) — they are
  engine machinery, not app-level API; barrel consumers cannot call them, and
  the members no longer freeze the class shape. Public read-only surface
  stays: `targetIds`, `duplicateTargetIds`, `scopePrefix`.
- **Single registry source:** the default host reads
  `HintController.registry` (public getter), so a custom host and the engine
  can no longer desync.
- **Diagnostics reach the engine:** the default host hands the engine the
  controller's handler (`HintController.diagnostics`, public getter) —
  overlay failures are no longer silent in the default wiring.
- **Breaking:** `HintSkipReason.targetNotRendered` → `overlayUnavailable`
  (label `target-not-rendered` → `overlay-unavailable`) — the check is about
  the overlay, not a particular target. Update exhaustive `switch`es and any
  log scrapers matching the old label.
- **Typo filtering preserves tour fields:** release-path typo filtering
  (`_withoutTypoSteps`) used a partial reconstruction that silently dropped
  `autoScroll` — fixed by routing through the internal `hintTourWithSteps`
  (not part of the public API).
- **Step lifecycle hooks, visit semantics:** **Breaking** rename
  `onBeforeAction`/`onAfterAction` → `onStepEnter`/`onStepExit`. They now
  bracket a *step visit* — enter once on first activation, exit once when the
  visit ends (step change, finish, skip, abort). Order is
  `old.exit → new.enter`; hooks are serialized and awaited (a throwing hook
  is logged, the chain continues). Target vanish/reappear no longer re-fires
  enter. Previously exit only ran on Active→Active (never on finish), enter
  could run before the previous exit, and vanish/reappear double-fired enter.
- **Content is the constructor path:** **Breaking** — see the
  `HintStep(content:)` entry above; `HintStepContent` is the slot type the
  getters return and every content slot takes (`HintStep.content`,
  `HintTooltip.content`). JSON wire keeps the flat `title`/`description`
  keys.
- **`DefaultTooltip` loses its slot params:** **Breaking** — `content:` and
  `showActions:` leave the public constructor (they were the engine's
  multi-content slot machinery). The public surface is `step`/`ctx`/
  `labels` — what a `tooltipBuilder` composes with; informational
  `additionalTooltips` slots render through the internal `HintSlotTooltip`
  (not exported).
- **`startOnce` — show-once from the box:** `HintController.startOnce(tour,
  mark:, version:)` runs `shouldShow` → `start` → `markShown` per the
  `HintMarkPolicy` (see above). The version gate comes from
  `HintTour.minShowVersion` (new optional wire key). Replaces the
  hand-rolled gate + idle-listener glue.
- **Offer `pageId` is optional:** `showHintTourOffer(pageId:)` defaults to
  `tour.id` (per-page decline key `offer:<tourId>@<tourId>`). Explicit
  call sites are unchanged.
- **Enums closed in 1.x:** dartdoc on `HintSkipReason`, `TooltipPosition`,
  `FocusShape`, `HintMissingTargetPolicy` and
  `HintTourOfferResult` — no new values before 2.0; exhaustive app-side
  `switch`es are safe. (`HintSkipEvent` fields stay extensible.)
- **Tap behaviors (`HintTapBehavior`):** **Breaking** — `tapOnTarget: bool` +
  `onTapTarget:` (and the overlay pair) collapse into one sealed
  `HintTapBehavior` per region: `targetTap`/`overlayTap` with
  `advance()` (default) / `ignore()` / `custom(onTap)`.
  Migration: `tapOnTarget: false` → `targetTap: const HintTapBehavior.ignore()`;
  `onTapTarget: cb` → `targetTap: HintTapBehavior.custom(cb)`.
  JSON wire keeps the historical bool keys (`true` ⇔ advance, `false` ⇔ ignore).
- **One scrim painter:** resolver-anchored `ScrimHolePainter` is gone;
  `RectScrimPainter` is the single painter (waiting = empty holes = full dim).
  `holeShape`/`scrimClipPath` live on `RectScrimPainter`. Focus fallback
  order is one chain (`resolveFocusShape`/`resolveFocusPadding` →
  the internal focus-padding default).
- **Overlay trusts the machine for waiting/active:** the overlay reads
  `HintActive` vs waiting from the machine state instead of re-deriving from
  the registry alone (same-frame unregistration still falls back to waiting
  as a desync-guard).
- **Internals under `lib/src/`:** `lib/engine/` and `lib/widgets/` moved to
  `lib/src/engine/` and `lib/src/widgets/` — deep imports
  `package:hintful/engine/...` / `package:hintful/widgets/...` no longer
  resolve. The only supported import is `package:hintful/hintful.dart`.
- **Removed adapter stubs:** the comment-only `lib/src/adapters/*` recipes
  (bloc/riverpod/provider/getx) are gone — wire via `controller.state`
  (`ValueListenable<HintState>`) in your app; see README/`doc/`.
- **Explicit barrel `show` lists:** every export names its symbols — a new
  public class in an existing file can no longer leak into the API by
  accident. `HintStepContent`, `HintTapBehavior` (the `advance()` /
  `ignore()` / `custom()` factories — the concrete subclasses are internal)
  and `HintSkipEvent` are in; render internals, the register-path,
  diagnostics helpers and `kHintFocusPadding` are out.
- **Structural JSON validation:** `HintTour.fromJson`/`HintStep.fromJson`
  throw a `FormatException` (with the offending tour/step in the message)
  on missing or empty `id`/`steps`/`targetId` instead of a raw `TypeError`
  — or, for empty `steps`, a release-only `RangeError` from the machine.
  Unknown enum names stay tolerant (warn + default, unchanged).
  `HintController.start` also refuses an empty tour in release (debug keeps
  the constructor assert).
- **Offer records the shown-state:** `showHintTourOffer` now runs the
  accept path through `startOnce` — an accepted tour is marked shown per
  `mark:` (`HintMarkPolicy.onAnyExit` by default — see the slimming block),
  out of the box. The documented "record via `startOnce` after the offer"
  composition was impossible (busy controller) and is gone.
  The `minVersion:` parameter is gone — declare
  `HintTour.minShowVersion` on the tour instead (both the offer gate and
  `startOnce` read it).
- **Offer labels are themeable:** new `HintTheme.tourOfferLabels` — the
  "Want a tour?" dialog's default copy joins the design system alongside
  `tooltipLabels`; `showHintTourOffer(labels:)` still overrides per call
  (omitted — the theme's labels; zero-config English unchanged).
- **Honest diagnostics:** a busy `start` in release now no-ops *before*
  typo classification — it no longer emits `unknownTarget` skip events for
  a tour that never ran, nor clobbers the running tour's registry diff;
  and a throwing `onStepEnter`/`onStepExit` hook is logged unconditionally
  (was debug-only), honoring the "a throwing hook is logged" contract.
- **One `overlayUnavailable` per tour:** a persistent "nowhere to draw"
  condition now reports a single skip event per tour (was: one per state
  change) — consumer analytics no longer double-count it. Failures inside
  the opt-in `autoScroll` path are logged in debug instead of being
  swallowed by a blanket catch.
- **Slimmer barrel:** **Breaking** — the factory trio (`HintTourFactory`,
  `InMemoryHintTourFactory`, `FetcherHintTourFactory`) is removed; the
  server-driven path is `HintTour.fromJson` + your HTTP client. Top-level
  `compareVersions` leaves the core (the `hintful_prefs` companion exposes
  a public one). The concrete tap
  subclasses (`HintTapAdvance`/`HintTapIgnore`/`HintTapCustom`) and
  `HintController.withHost` are internal — use the `HintTapBehavior.*`
  factories and `HintController.test` instead.
- **Naming freeze (pre-tag):** **Breaking** — `HintStep.waitTimeout` →
  `stepTimeout` (symmetric with the tour-level `stepTimeout`),
  `HintTooltip.position` now defaults to
  `TooltipPosition.auto` (was required). JSON wire key `waitTimeoutMs`
  is unchanged — old payloads keep parsing. (The transition preset rename
  `HintCurve` → `HintEntryAnimation` happened during development; the whole
  system is removed by the slimming block above.)

## 0.7.0 — honest presets, tolerant JSON, tighter surface

**Breaking:** `HintSkipReason.targetUnmountedDuringStep` is gone — drop the case
from an exhaustive `switch` — and four engine symbols leave the public barrel.

- `HintCurve.easeOut` is a real preset: fade + scale 0.96 → 1 on `Curves.easeOut`,
  200 ms. It used to behave like "no animation".
- `fromJson` tolerates an unknown enum name: it falls back to the field default
  and is reported through the new `onWarning` callback (also on
  `FetcherHintTourFactory`) instead of throwing.
- Exported `hintTransitionDuration` — the reduce-motion helper the presets use,
  so a custom `tooltipBuilder` shares the same contract.
- Duplicate `targetId` warnings now actually print in debug builds; `onWarning`
  still fires.
- `autoScroll` no longer flashes the tooltip in a screen corner: while the
  target is still off screen the tooltip waits at the edge it is coming from
  and rides the scroll onto it. The position watch dropped the tooltip for the
  whole animation — an unpainted target has no compositor transform — and the
  placement parked it in the top-left corner.
- Removed `findClosestTargetId`; `formatHintSkipped`, `editDistance`,
  `CompositorHintResolver` and `UnpositionedHintResolver` are no longer exported.
  They stay public inside `lib/engine/` for the package's own tests, and custom
  hosts keep `HintPosition`, `PositionedHint`, `UnpositionedHint` and
  `HintPositionResolver`.
- Dropped the stale `hintful_bloc/` references from `.pubignore` and
  `analysis_options.yaml`.

Docs: README rebuilt around badges, a demo section and the `withHint`/l10n paths;
`doc/best_practices.md` now covers 0–21 with an index; the FAQ grew to ten answers.

## 0.6.2 — autoScroll, withHint, target focus and l10n

- `autoScroll` on `HintTour`/`HintStep` (opt-in, `false` by default) — brings offscreen targets into view.
- `HintTarget(focusShape/padding)` as target default — `HintStep` overrides; no per-step duplication for round icons.
- `withHint` extension: `child.withHint('id')` sugar over `HintTarget`.
- `titleBuilder`/`descriptionBuilder` on `HintStep`/`HintTooltip` — l10n via `BuildContext` without threading it through `AppTours`.
- Example: `Step scroll` (per-step `autoScroll`), `L10n` (builder), `withHint` on `filter-all`, `entry-5` circle, intro `autoScroll: true`, full custom `TweenAnimationBuilder` + float.

## 0.6.1 — flicker-free spotlight

- First-frame seed from RenderBox — no white flash on start/step change.
- Global scrim — no bottom gap on scroll.
- Scroll-synced holes — scrim + tooltip move with content in same frame.

## 0.6.0 — spotlight correctness (saveLayer scrim, rect targets, honest states)

- First-frame content: positions seed synchronously from the targets'
  own render objects (`initState` + step changes), so dim + hole + tooltip
  render on the very first frame — no normal-UI flash on start, no stale
  step on transitions. Scroll-driven motion follows the compositor
  synchronously (ancestor Scrollables observed) — no one-frame lag while
  the screen scrolls. Live compositor resolvers upgrade in behind
  (same values ± subpixel).
- One scrim mechanism for every shape: fullscreen dim + `BlendMode.clear`
  holes in an isolated layer (no boolean geometry, overlap-correct); blur
  clips to one even-odd path. Removed the strips path (`scrimStrips`,
  pre-1.0 breaking note).
- First shown step renders dim + hole together with the tooltip (was:
  tooltip without dim until a step change).
- `targetRect` steps: immediate Active, static spotlight with tooltip;
  explicit `overlay` provider for zero-target tours.
- Offscreen/culled targets: no frozen spotlight — retracted while
  unpainted, remounted on return; bringing targets into view stays the
  app's job. No stale tooltip on step change (transition frame unmounts).
- Single-step hints keep no action row (no meaningless Done).
- Hardened holes: over-shrunk padding degrades to full dim, corner radius
  clamped, never throws.
- DRY: one hole geometry, one tooltip content/placement/entry source,
  `FocusShape` end to end, one machine step-entry path.
- Accessibility: sprung honors reduce-motion; offer dialog awaits start.

## 0.5.0 — production hardening (l10n, skip-missing, safe start, scopes)

Four battle-feedback fixes, all backward-compatible:

- Localization hook: `HintTooltipLabels` (`engine/labels.dart`) — `skip/
  back/next/done`, waiting placeholder `preparing`, screen-reader
  `announceStep`. Wired as `HintTheme.tooltipLabels` (English default) + a
  per-tooltip `DefaultTooltip(labels:)` override — localize once in the
  theme instead of duplicating the tooltip layout per language. The
  waiting-phase "Preparing…" comes from the labels too.
- Missing-target policy: `HintMissingTargetPolicy.skipStep` vs `abortTour`
  (default) — on `HintTour` (incl. `fromEnum`, JSON) with a per-step
  override. A timed-out step is diagnosed (`timeout`) and the tour continues;
  skipping the last step finishes normally. Pair with a short `waitTimeout`
  (`Duration.zero` skips instantly, no waiting flash). New machine effect
  `StepSkippedEffect`.
- Safe start: `isIdle`, `tryStart` (false when busy — no assert, no
  state change), `restart` (silently replaces the running tour),
  `tryShowHint`. `start` keeps its debug contract.
- Controller scopes: `scopePrefix` isolates
  tabs/split-view sharing one registry — foreign ids neither activate steps
  nor count as typo candidates.

## 0.4.0 — server-driven tours + adapters

- `HintTour`/`HintStep`/`HintTooltip` now `fromJson`/`toJson` (`specs.dart:194`) — `steps` are `title/description` + `position`/`moreTargets`/`moreTooltips`, `tooltipBuilder` stays code-side. `FetcherHintTourFactory` (`engine/tour_factory.dart`) takes your fetcher `(Uri)=>Future<String>` — no `http` dependency in `hintful`.
- Adapters `lib/src/adapters/{bloc,riverpod,provider,getx}.dart` — thin `ValueListenable→Cubit/Provider` stubs (~15 lines) over `HintController.state`, core stays `dart:ui+widgets`.

## 0.3.0 — control, accessibility, versions, visual depth

**New capabilities**

- Programmatic control: `previous()`/`goTo()`, `HintTour.disableBackButton`
  (Android back/route pop), Shift+Tab backwards navigation.
- Smart positioning (full): auto-flip re-picks the side on scroll,
  keep-in-safe-area (notch/home indicator), the tooltip never covers the
  spotlighted targets, tail (arrow) ties the tooltip to its target.
- Accessibility on by default: screen-reader step announcements, keyboard
  navigation (Tab/Shift+Tab/Enter, Esc = skip), reduce-motion
  (`hintTransitionDuration`), fits at 2× text scale, WCAG AA contrast in the
  default themes, focus restored after the tour.
- Versioned hints: `HintStore` (`shouldShow(key, minVersion:)` /
  `markShown`), the "show again" semantic is a version bump, not flag
  wiping; `InMemoryHintStore` ships in the core, persistent implementations
  live app-side.
- Multi-target steps: several elements spotlighted at once, each with its
  own scrim hole. Multi-content: several tooltips around one target that
  never overlap each other or the targets.
- Tap regions: tap-on-target vs tap-on-overlay with per-step callbacks and
  tap position; scroll-through — the page scrolls under an active tour.
- Blur scrim and a pulsing ring as theme options (`HintTheme.imageFilter` /
  `showPulse`); the default stays the cheap plain dim. The pulse renders
  above the blur (its own global layer).
- Enum-typed tours: `HintTour.fromEnum` — the exhaustive `stepFor` switch
  makes adding/removing a step a compile error.
- "Want a tour?" pre-dialog: `showHintTourOffer` with an "Apply to all
  pages" checkbox; declines persist per page or globally in the store.
- UX polish: Skip is hidden on the last step of a tour (a lone Skip was
  already meaningless in 0.2.0); the scrim no longer flashes a wrong
  full-screen dim on the first frame of a step.
- Example app reworked into a demo playground (`main`/`home_screen`/
  `demo_tours`): visual demo card with blur/pulse style switcher and one
  button per feature, 10 smoke tests.

**Adapters**

- `hintful_bloc` 0.1.1: `HintCubit` — a thin Cubit over `HintController`
  (no logic of its own; apps wanting an event layer write their own
  `Bloc<AppEvent, HintState>` on top).

## 0.2.0 — unified "hint" naming

**Breaking:** the public API is renamed to a single `Hint` family —
`ShowcaseController` → `HintController`, `ShowcaseTarget` → `HintTarget`,
`ShowcaseTheme` → `HintTheme`, `TourState` → `HintState` (and `Idle`/
`Waiting`/`Active`), `TourSpec`/`StepSpec` → `HintTour`/`HintStep`,
`TargetRegistry` → `HintTargetRegistry`, `TourOverlayHost` → `HintOverlayHost`.
Files `showcase_target.dart`/`showcase_theme.dart` → `hint_target.dart`/
`hint_theme.dart`. `TooltipPosition`, `DefaultTooltip` and diagnostics
(`HintSkipReason`, `HintDiagnosticsHandler`) keep their names — `tooltip` is
the accepted term for the visual element, diagnostics were already `Hint`.
No behavior changes.

## 0.1.0 — stage 0 (early engine)

- Registry-based targets (`ShowcaseTarget(id:)`) — no `GlobalKey`; duplicate-id
  policy "last wins", self-cancellation by identity in `dispose`.
- Clean state machine (`TourState`), data-driven tests (table + fuzz).
- `ShowcaseController`: `start/next/skip/finish`, `showHint` for single tips,
  DX3 validation with closest-id candidates for typos; headless-capable
  (no overlay host required).
- Overlay engine on `CompositedTransform`: scrim hole follows the target via the
  compositor (zero scroll math), tooltip in a global layer with auto-flip
  placement (stage 0: sides + keep-in-screen).
- Wait-for-target with timeout, deferred/lazy targets.
- `ShowcaseTheme` ThemeExtension, light/dark from `ColorScheme`.
- DX1 diagnostics: every failed show reports a reason (`timeout`,
  `userSkipped`, `unknownTarget`, ...) to a `HintDiagnosticsHandler`.
- `TourOverlayEngine` (hidden mechanics) + `defaultOverlayHost()` factory;
  keyboard: Tab/Enter = next, Esc = skip.
- Example app (`example/`): 4-step tour with deferred target, light/dark,
  `showHint`; smoke tests, tour flow tests, integration benchmark skeleton.