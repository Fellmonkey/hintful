# Competitive analysis: hintful vs. tours / hints / onboarding solutions

Research backing the "Why hintful" section of the README. Data collected
**October 2026**: pub.dev metrics, and the rivals' **sources** (repositories
cloned and read directly — not their READMEs' claims). JS libraries were
checked via npm registry and their published bundles. Items that could not be
confirmed against a primary source are marked *(not verified)*.

## 1. Flutter packages

| | hintful | tutorial_coach_mark | showcaseview | flutter_intro | overmark | hint_kit |
|---|---|---|---|---|---|---|
| Weekly downloads | new | ~208K | ~237K | ~2.3K | ~97 | ~855 |
| Last release | 1.0.0 | v1.3.4, Aug 2026 | v5.1.0, Jun 2026 | v3.4.0, **Oct 2024** | v0.2.0, Aug 2026 | v1.3.1, Oct 2026 |
| Target reference | string id → registry | `GlobalKey` or manual `TargetPosition` | widget in tree (registry in v5) | generated `GlobalKey` | `GlobalKey` | *(not read)* |
| Follows scroll live | **yes** — compositor follower + same-frame scroll shift | no — re-measure on `didChangeMetrics` only | no — re-measure on rebuild; no `ScrollNotification` in `lib/` | no | **yes** — `ScrollPosition` listener re-measure | *(not read)* |
| Missing/late target | first-class waiting state + timeout policy | skip silently (`skipToNextAvailable`) | polling inside `scrollIntoView` | throws an exception | readiness polling with timeout | waits across route changes |
| Persistence | versioned `HintStore` + offer dialog | none | none | none | `showOnce` + pluggable storage | `TourStorage` |
| Diagnostics | skip reasons + typo suggestions | — | — | exceptions | — | analytics observer |
| Theming | `ThemeExtension` | builder params | params | `maskColor` | theme object | 10 presets |
| A11y | keyboard + focus restore + semantics + contrast tests in CI | open issues (#228) | open issues (#622) | — | declared options | declared |
| JSON-serializable tours | **yes** | no | no | no | no | *(not read)* |

### Per-package notes

- **tutorial_coach_mark** (~208K weekly, v1.3.4): tour lives in one
  `OverlayEntry` inserted post-frame; target position is
  `GlobalKey → RenderBox → localToGlobal`, re-measured only on
  `didChangeMetrics`. No scroll listener in the package. Mask is a
  `CustomPainter` with an even-odd hole. Recurring issue themes (~160 open):
  overlay surviving navigation (#216), overlay blocking scroll (#204),
  gesture/animation races (#175/#183, #661-analog), TalkBack/VoiceOver (#228),
  flicker during pulse (#230/#231). No persistence — show-once is each app's
  own code.
- **showcaseview** (~237K weekly, v5.1.0): registry-based (`ShowcaseService`),
  singleton `OverlayManager`, one `OverlayEntry` per scope; cutout via
  `ClipPath` + `Path.combine(difference)` over dim/blur. Position recalculated
  in `build` → post-frame → `OverlayManager.update()`; grep confirms **no**
  `ScrollNotification` anywhere in `lib/`. Auto-scroll wraps
  `Scrollable.ensureVisible` with a settle-poll (60 ms × up to 120). Known
  issue themes (~344 open): overlay surviving back-navigation (#666), crashes
  on unmounted targets (#662), animation-dispose races (#661), a11y (#622).
  No persistence.
- **flutter_intro** (~2.3K weekly): `static OverlayEntry` + static geometry —
  global isolate state; dimming via blend modes (`ColorFiltered srcOut` +
  `dstOut`), no painter; no scroll handling at all (throttled re-render on
  resize only); README requires a manual `dispose()` on the back gesture or
  the overlay leaks. Last release Oct 2024.
- **overmark** (~97 weekly, v0.2.0): `GlobalKey` anchors + readiness polling
  (3 s timeout); **does** attach a `ScrollPosition` listener (so it repositions
  live — by re-measuring, unlike hintful's compositor following);
  `SpotlightPainter` with `BlendMode.clear`; passthrough tap gates; pluggable
  `OvermarkStorage` + `showOnce`; `PopScope`; theme object. Very small
  adoption.
- **hint_kit** (~855 weekly, v1.3.1, Oct 2026): overlay engine shared by
  tooltips/tours/persistent hints; tours survive route changes (waits for
  remounted targets, `stepTimeout`); `TourStorage` show-once; analytics
  observer; 10 presets; a11y declared. Scroll mechanics *(not read)*.
- **features_tour** (~1.45K weekly): controller + numeric step index instead
  of declarative marking; `onBeforeIntroduce` lets the app scroll manually;
  ships `shared_preferences` persistence.

## 2. JavaScript libraries (approach context)

- **driver.js** (v1.10.1, ~2.29M weekly npm, MIT, zero deps): overlay is one
  SVG `evenodd` path (full-screen rect + rounded cutout); `scroll`+`resize`
  listeners throttled through `requestAnimationFrame`, plus a
  `MutationObserver`; position from `getBoundingClientRect()`.
- **shepherd.js** (v15.3.0, ~347K weekly, AGPL/commercial): Floating UI with
  `autoUpdate` for the tooltip; the overlay path is recomputed **every frame**
  (rAF) and clipped by the target's whole scroll-parent chain — the most
  advanced scroll handling found in this survey.
- **intro.js** (v8.6.0, ~188K weekly, AGPL/commercial): no cutout — the
  target is lifted with `z-index: 9999999` and the dim is a giant
  `box-shadow … 0 0 0 5000px` from the helper layer; tours refresh on resize
  only, no live scroll listener (hints mode has debounced scroll+resize).
- **react-joyride** (v3.2.0, ~1.39M weekly, MIT): Floating UI +
  `useTargetPosition` hook listening to scroll on every scroll-parent + window,
  `resize`, `ResizeObserver`; SVG `evenodd` overlay + separate spotlight frame.
- **reactour** (v1.19.4, last release May 2024, ~58K weekly): SVG `<mask>`
  overlay; only resize + `MutationObserver`, **no** scroll listener; peer-deps
  capped at React 18.

Takeaway: live scroll-following is the **norm** in the JS world; in Flutter it
is still rare — hintful and overmark are the two confirmed to do it
(hint_kit's mechanics were not read). Only `intro.js` solves "highlight"
without a real cutout.

## 3. SaaS platforms — a different category, not libraries

Pendo and Appcues ship official Flutter SDKs (pub.dev); Userpilot lists
Flutter; UserGuiding is explicitly web-only ("relies on JavaScript");
Chameleon/WalkMe Flutter support *(not verified)*. These are platforms: no-code
builders, analytics, targeting/segmentation, checklists, NPS, session replay —
tours are one feature behind a vendor account and a remote config. They
compete on a different axis than an in-repo, dependency-free engine.

## 4. What is *not* different (shared state of the art)

- **Punch-hole scrim** (`CustomPainter` + `BlendMode.clear`) — tutorial_coach_mark,
  showcaseview and overmark all cut a hole too. hintful's version is
  overlap-correct and shape-aware (rect/circle/rounded, negative padding), not
  a new paradigm.
- **A single `OverlayEntry` per tour** — also showcaseview's approach.
- **Zero idle engine cost** — all three solutions measured by the benchmark
  hold 0 engine instances while idle.
- **Zero runtime dependencies** — common in this niche.

## 5. Benchmark caveats

The numbers in the README's Performance block are recorded by this repo's own
CI (`flutter_bench_contract`) on **one** profile Android emulator. They are
reproducible, not third-party audited. The scroll-coupling contract (S4)
passes for hintful and is marked *unsupported* for the rivals' drivers — the
benchmark proves hintful's side only; the "rivals don't follow scroll" claim
comes from reading their sources (§1), not from the benchmark. Size rows are
hintful-only because the rival scenes were never shipped as size targets.

## 6. Honest limitations (full list)

1. **New package** — no production track record, against rivals with years of
   history and 200K+ weekly downloads each.
2. **Idle tree footprint** — with a controller in the tree but no active tour,
   hintful adds 4 widget elements (measured rivals add 2–3). The engine itself
   holds zero instances/listeners; the 4 elements are the controller's scope.
3. **Binary size** — ~73–82 KB native AOT, ~+57 KB web bundle (includes the
   default tooltip and the placement engine). A real cost for a
   single-tooltip micro-need.
4. **No dedicated IME/keyboard-avoidance code** — a keyboard over the
   spotlighted field is handled indirectly: `MediaQuery` rebuilds the overlay
   and the placement delegate re-places the tooltip; there is no explicit
   `viewInsets` logic.
5. **No built-in tooltip entry animation** — by design; animate inside
   `tooltipBuilder`.
6. **One tour at a time** — nesting/concurrency is an assert, not a feature.
7. **No `RepaintBoundary` in the library** — repaints are kept cheap by
   construction (minimal `shouldRepaint` fields, cached tooltip slots,
   at-rest zero repaints); add one at the call site if profiling shows need.
8. **Not a platform** — no no-code builder, no analytics/event tracking, no
   remote config, no segmentation. Tours are code, or JSON you fetch yourself.
