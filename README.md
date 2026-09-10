# hintful

**Hints & onboarding tours for Flutter.** Spotlight targets, tooltips, coach marks,
guided walkthroughs — a single source of truth for teaching users your product.

You wrap one widget in `HintTarget`, describe what to show in a `HintTour`,
and the engine renders, repositions and remembers it — without a single
hand-written overlay, scroll math or duplicated per-screen styling.

---

## Why another hint library?

Every Flutter hint/tour library you've seen is built on the same two ideas:
`GlobalKey` + a full-screen `OverlayEntry` that the library manually positions,
scrolls and lays out. That model is precisely why tours break:

- tooltips overflow by 1px, or overlap their own target;
- the overlay jumps off-screen mid-scroll, then crashes with
  `This widget has been unmounted` when the target scrolls out of view;
- on the first run — when targets are still being built — the tour silently dies
  because the widget it wants doesn't exist yet;
- every hint hard-codes its own colors, so the tour never matches your design system;
- pick a state-management stack and you're locked into it forever.

`hintful` throws that model away.

## What's different

| Old way (`GlobalKey` + overlay) | `hintful` |
|---|---|
| Manual position / scroll / re-layout | **CompositedTransform** — tooltip and scrim follow the target every frame, zero scroll math, overflow impossible |
| References to widget contexts | **Registry by id** — `HintTarget(id: 'filters')` registers/unregisters itself; nothing to unmount |
| "Wait until the widget is built" by hand | **Wait-for-target** — a tour waits for a deferred target instead of dying |
| Per-hint hard-coded styling | **ThemeExtension** — hint inherits your design system, light and dark, from `Theme.of` |
| Tied to Bloc/Riverpod/… | **Framework-agnostic core** — vanilla `ValueListenable<HintState>`, no state-management imports |
| Overlay mounted even when idle | **Zero-idle cost** — zero engine widgets in the tree until a tour actually starts |

## What you write

```dart
// 1. Wrap the thing you want to explain
HintTarget(
  id: 'exerciseSelector',
  child: ExerciseSelector(),
)

// 2. Declare the tour — data, not widgets
final introTour = HintTour(
  id: 'intro',
  steps: [
    HintStep(
      targetId: 'exerciseSelector',
      title: 'Pick a movement',
      description: 'Filter by muscle, equipment or name.',
    ),
    HintStep(
      targetId: 'addSet',
      title: 'Log your set',
      description: 'Weight × reps, one tap.',
    ),
  ],
);

// 3. Wire once, show once
final controller = HintController(
  overlayHostBuilder: defaultOverlayHost(),
);
controller.start(introTour);
```

No `GlobalKey`, no `OverlayEntry`, no `ScrollController`, no manual position.
That's the whole tour — and it already handles light/dark, scrolling and
deferred targets.

```dart
// Just one tip? No tour needed:
controller.showHint(
  HintStep(targetId: 'addSet', title: 'Swipe left to delete a set'),
);
```

## Fast — measured, not promised

One scene, three libraries, profile Android emulator — recorded by CI into
`benchmark/benchmarks.json` and rendered into the table below by the bot, so
the numbers have a single source of truth. Table, charts, methodology:
[Performance](#performance).

## Zero-config, then total control

Out of the box, `title`/`description` steps render in a default tooltip under
a default theme — the tour above is already complete. When you need more, the
API grows rung by rung, each optional: `HintTheme` styles → `HintTooltipLabels`
(button texts, waiting placeholder, screen-reader announcements) → a fully
custom tooltip through `tooltipBuilder`. Your design system, your call.

## Diagnosis over mystery

When a hint doesn't show, you'll know why in one log line:

```
[hintful] statsIntro step 2 not shown: timeout (target 'statsPeriodSelector') — target 'statsPeriodSelector' did not appear within 0:00:03.000000
```

Not "it just didn't appear." If you typo a `targetId`, `hintful` tells you loudly in
debug — with the closest candidates.

## Accessibility, on by default

- **Screen readers**: every step is announced as "Step N of M: <title>".
- **Keyboard**: Tab/Shift+Tab move forward/back, Enter = next, Esc = skip;
  the tour manages focus and returns it to the element you were on before
  it started.
- **Reduce motion**: with the system setting on, transitions are instant.
- **Text scale**: the tooltip fits on screen at 2× text scale (content
  scrolls instead of overflowing).
- **Contrast**: the default theme meets WCAG AA (4.5:1) for text and
  buttons, in light and dark.

## Works anywhere

The core is framework-agnostic by construction: it imports only `dart:ui` +
`flutter/widgets`, no state-management package. Vanilla Flutter works out of the
box via `ValueListenableBuilder` — zero dependencies. Bloc/Riverpod/Provider/GetX
wiring ships as copy-paste recipes in `lib/src/adapters/` (bring your own package).

## Features

**Tour control**

- `start/next/previous/goTo/skip/finish`; safe variants
  `tryStart/restart/tryShowHint` + `isIdle` — no manual guards before starting
- Wait-for-target for deferred and lazy-loaded widgets, with timeout + diagnosis
- Missing targets: `HintMissingTargetPolicy.skipStep` (tour default or per-step)
  skips an absent target with a `timeout` diagnosis and continues the tour;
  short/`Duration.zero` `waitTimeout` for conditionally-absent targets
- Scoped controllers: `scopePrefix` isolates tabs/split-view sharing one
  registry (foreign ids neither activate steps nor false-fire typo candidates)
- `disableBackButton` owns the Android back button while a tour is active;
  Skip auto-hides on the last step of a multi-step tour (Done does the
  same); a single-step hint keeps no action row at all

**Rendering**

- CompositedTransform tooltip + scrim — follows scroll/layout/animation for free
- Smart positioning: auto-flip to the side with room, keep-in-safe-area,
  and a tail (arrow) tying the tooltip to its target
- Multi-target steps: several elements spotlighted at once, the tooltip
  avoiding the other spotlighted targets
- Multi-content: several tooltips around one target, guaranteed not to
  overlap each other or the targets
- Optional blur scrim and pulsing ring (theme options; the default stays the
  cheap plain dim)
- Focus shapes (rectangle/circle/rounded) + padding (including negative
  shrink), static rect spotlights (`targetRect` — no widget needed), and
  scroll-into-view: an offscreen target is brought on screen with its step
- Entry animation in three rungs: none by default; the `sprung` bounce per
  step (`transitionCurve` + `transitionDuration`); anything custom through
  `tooltipBuilder` (the engine still places it) — all skipped under the
  system reduce-motion setting
- Tap regions: tap-on-target vs tap-on-overlay with per-step callbacks and
  tap position; scroll-through — the page scrolls under an active tour

**Content & reuse**

- Enum-typed tours: `HintTour.fromEnum` — the exhaustive `stepFor` switch
  makes adding/removing a step a compile error
- Versioned hints (`HintStore`): show once per app version —
  `shouldShow(key, minVersion:)` before start, `markShown` on exit
- "Want a tour?" pre-dialog (`showHintTourOffer`, own `HintTourOfferLabels`):
  declines persist per page or globally, the tour stays reachable from other
  entry points

## Server-driven tours

No extra dependency: `HintTour.fromJson/toJson` + `FetcherHintTourFactory` (bring your own `http`/`dio`):
```dart
final factory = FetcherHintTourFactory(
  baseUrl: 'https://cdn.example.com/tours',
  fetcher: (uri) async => (await http.get(uri)).body, // your client
);
final tour = await factory.fetch('onboarding');
await controller.start(tour);
```

## Getting started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  hintful: ^0.6.2
```

```dart
import 'package:hintful/hintful.dart';
```

See `example/` for working demos of every feature above — shaped holes,
blur/pulse styles, custom animated tooltips, JSON tours, tap regions, the
offer dialog, and the versioned intro.

---

<!-- bench:start -->
## Performance

One scene, three solutions: the contract scenarios S1–S6 on a profile Android emulator plus the host size builds (S7). Values are the recorded goldens in `benchmarks.json` (refs `android` / `android-scv` / `android-tcm`). Methodology: `benchmark/README.md`; `benchmark/compare` hosts the rival drivers.

| Metric | hintful | showcaseview | tutorial_coach_mark |
|---|---|---|---|
| Idle tree diff (S1) | 4 | 2 | 3 |
| Idle resources (S1r) | 0 | 0 | 0 |
| Show latency (S2) | 140 ms | 181 ms | 885 ms |
| Update latency (S3) | 214 ms | 312 ms | 1441 ms |
| Active-step heap (S5) | 42 KB | 65 KB | 94 KB |
| Heap retained after hide (S6) | -59 B | -325 B | -91 B |
| Native AOT size | 75 KB | n/a | n/a |
| Web startup bundle delta | 49 KB | n/a | n/a |

**n/a** = not applicable for this solution. Scroll coupling (S4) is a two-sided in-scenario assert, not a numeric row: hintful re-anchors its content to the target under programmatic scroll on-device, while showcaseview and tutorial_coach_mark do not (their overlays consume pointer input). The idle-resources row (S1r) is declared on-device via `idleClasses` — 0 means the solution holds no live control-plane instances while idle. The size rows are hintful-only because the rival scenes were never shipped as size targets.

**Trend history:** [charts](https://fellmonkey.github.io/hintful/bench/)

![hintful benchmark metrics](docs/hint_metrics.png)

_Recorded 2026-09-09 16:18 UTC. Regenerate: dispatch the `bench-record` workflow with `record`._
<!-- bench:end -->
