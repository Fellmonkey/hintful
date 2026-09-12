# Changelog

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