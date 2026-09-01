# Changelog

## 0.3.0 — control, accessibility, versions, visual depth

**New capabilities**

- Programmatic control: `previous()`/`goTo()`, `HintTour.disableBackButton`
  (Android back/route pop), Shift+Tab backwards navigation.
- Smart positioning (full): auto-flip re-picks the side on scroll, keep
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