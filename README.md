# hintful

[![pub.dev](https://img.shields.io/pub/v/hintful.svg)](https://pub.dev/packages/hintful)
[![pub points](https://img.shields.io/pub/points/hintful.svg)](https://pub.dev/packages/hintful/score)
[![license](https://img.shields.io/github/license/Fellmonkey/hintful.svg)](https://github.com/Fellmonkey/hintful/blob/main/LICENSE)
[![CI](https://github.com/Fellmonkey/hintful/actions/workflows/ci.yml/badge.svg)](https://github.com/Fellmonkey/hintful/actions/workflows/ci.yml)

**Hints & onboarding tours for Flutter.** Spotlight targets, tooltips, coach marks,
guided walkthroughs — a single source of truth for teaching users your product.

You wrap one widget in `HintTarget`, describe what to show in a `HintTour`,
and the engine renders, repositions and remembers it — without a single
hand-written overlay, scroll math or duplicated per-screen styling.

## See it in action

[A hintful tour running over the example app](https://github.com/user-attachments/assets/3a92f95d-2265-4577-954a-63b32b208769)

_Recorded on the `example/` app. Try it live:
[fellmonkey.github.io/hintful](https://fellmonkey.github.io/hintful/)._

## Index

**Start here** — [See it in action](#see-it-in-action) · [Why hintful](#why-hintful) · [What you write](#what-you-write) · [Fast](#fast--measured-not-promised)

**What it does** — [Zero-config, then total control](#zero-config-then-total-control) · [Diagnosis over mystery](#diagnosis-over-mystery) · [Accessibility](#accessibility-on-by-default) · [Works anywhere](#works-anywhere) · [Features](#features) · [Server-driven tours](#server-driven-tours)

**Install & docs** — [Getting started](#getting-started) · [Documentation](#documentation) · [best practices](doc/best_practices.md#index) · [FAQ](doc/faq.md) · [Performance](#performance)

---

## Why hintful

Every Flutter hint/tour library you've seen is built on the same two ideas:
`GlobalKey` + a full-screen `OverlayEntry` that the library manually positions,
scrolls and lays out. That is exactly where tours break: the tooltip drifts a
pixel off or covers the control it points at, the overlay goes off-screen
mid-scroll and dies with `This widget has been unmounted`, and on a first run it
silently gives up because the target isn't built yet.

`hintful` throws that model away.

### What's different

| Old way (`GlobalKey` + overlay) | `hintful` |
|---|---|
| Manual position / scroll / re-layout | **CompositedTransform** — tooltip and scrim follow the target every frame, zero scroll math, overflow impossible |
| References to widget contexts | **Registry by id** — `HintTarget(id: 'filters')` registers/unregisters itself; nothing to unmount |
| "Wait until the widget is built" by hand | **Wait-for-target** — a tour waits for a deferred target instead of dying |
| Per-hint hard-coded styling | **ThemeExtension** — hint inherits your design system, light and dark, from `Theme.of` |
| Tied to Bloc/Riverpod/… | **Framework-agnostic core** — vanilla `ValueListenable<HintState>`, no state-management imports |
| Overlay mounted even when idle | **Zero-idle cost** — zero engine widgets in the tree until a tour actually starts |

_Zero-idle is about the engine: no overlay, entry or listener exists until a tour
starts. The thin `HintTarget` wrapper around your widget is the only idle
footprint — that's the `4` nodes in the S1 row of the benchmark table below._

## What you write

```dart
// 1. Wrap the thing you want to explain
HintTarget(
  id: 'exerciseSelector',
  child: ExerciseSelector(),
)
// ...or the one-liner sugar: ExerciseSelector().withHint('exerciseSelector')

// 2. Declare the tour — data, not widgets
final introTour = HintTour(
  id: 'intro',
  steps: [
    HintStep(
      targetId: 'exerciseSelector',
      content: HintStepContent(
        title: 'Pick a movement',
        description: 'Filter by muscle, equipment or name.',
      ),
    ),
    HintStep(
      targetId: 'addSet',
      content: HintStepContent(
        title: 'Log your set',
        description: 'Weight × reps, one tap.',
      ),
    ),
  ],
);

// 3. Wire once, show once
final controller = HintController();
controller.start(introTour);
```

No `GlobalKey`, no `OverlayEntry`, no `ScrollController`, no manual position.
That's the whole tour — and it already handles light/dark, scrolling and
deferred targets.

Localizing? Swap the strings for `titleBuilder`/`descriptionBuilder` inside
`HintStepContent` (`(c) => AppLocalizations.of(c)!.introTitle`): the copy
stays in your `AppTours` file and the `BuildContext` arrives from the
overlay.

```dart
// Just one tip? No tour needed:
controller.showHint(
  HintStep(
    targetId: 'addSet',
    content: HintStepContent(title: 'Swipe left to delete a set'),
  ),
);
```

**Production wiring** — store once, offer + show-once:

```dart
// once, at wiring (SharedPreferences / your storage)
final store = CallbackHintStore(
  read: (key) => prefs.getString(key),
  write: (key, value) => prefs.setString(key, value),
);
Hintful.configure(store: store); // every controller reads it

// optional ask-first dialog — gate + decline + startOnce under `mark:`
await showHintTourOffer(
  context: context,
  controller: controller,
  tour: introTour(minShowVersion: appVersion),
  pageId: 'Home',
  // mark: HintMarkPolicy.onAnyExit, // default: finish/skip/timeout all count
);

// or start directly; `mark:` defaults to HintMarkPolicy.onAnyExit
await controller.startOnce(introTour(minShowVersion: appVersion));
```

No store configured? A session `InMemoryHintStore` keeps show-once working
for this run only (debug prints a one-time warning) — configure a persistent
store for real once-per-version semantics. The ready-made shared_preferences
store ships in the [`hintful_prefs`](https://pub.dev/packages/hintful_prefs)
companion package. Wire format ↔ Dart params: `stepTimeout` ↔
`waitTimeoutMs`, tap-bools `tapOnTarget`/`tapOnOverlay` ↔
`HintTapBehavior.advance()`/`ignore()`.

## Fast — measured, not promised

One scene, three libraries, profile Android emulator — recorded by CI into
`benchmark/benchmarks.json`, rendered straight from that file into the table
below — one source of truth for every number. Table, charts, methodology:
[Performance](#performance).

## Zero-config, then total control

Out of the box, `title`/`description` steps render in a default tooltip under
a default theme — the tour above is already complete. When you need more, the
API grows rung by rung, each optional: `HintTheme` styles → `HintTooltipLabels`
(button texts, waiting placeholder, screen-reader announcements) →
`titleBuilder`/`descriptionBuilder` for
l10n → a fully
custom tooltip through `tooltipBuilder`. Your design system, your call.

## Diagnosis over mystery

When a hint doesn't show, you'll know why in one log line:

```
[hintful] statsIntro step 2 not shown: timeout (target 'statsPeriodSelector') — target 'statsPeriodSelector' did not appear within 0:00:03.000000
```

Not "it just didn't appear." If you typo a `targetId`, `hintful` tells you loudly in
debug — with the closest candidates.

The reasons and their fixes: [FAQ §1](doc/faq.md#1-my-hint-didnt-show--why);
wiring your own handler for analytics:
[best practices §12](doc/best_practices.md#12-diagnostics--trust-the-log).

## Accessibility, on by default

- **Screen readers**: every step is announced as "Step N of M: <title>".
- **Keyboard**: Tab/Shift+Tab move forward/back, Enter = next, Esc = skip;
  the tour manages focus and returns it to the element you were on before
  it started.
- **Reduce motion**: with the system setting on, custom tooltip entries
  check `MediaQuery.disableAnimations` and render instantly (the default
  tooltip has no animation of its own).
- **Text scale**: the tooltip fits on screen at 2× text scale (content
  scrolls instead of overflowing) — writing copy that never needs it:
  [FAQ §5](doc/faq.md#5-text-overflows-at-20-scale).
- **Contrast**: the default theme meets WCAG AA (4.5:1) for text and
  buttons, in light and dark — asserted across brightness and colour seeds
  in the theme tests.
- **Targets**: `HintTarget(semanticsLabel: ...)` labels the spotlighted
  widget itself for the screen reader — so an icon-only button is not
  announced as a blank.

## Works anywhere

The state/data core is framework-agnostic by construction — `controller`,
`machine`, `registry`, `specs`, `store` and `diagnostics` import only
`dart:ui`/`flutter/foundation`/`flutter/widgets`, and nothing
state-management related. (Render mechanics and `HintTheme` are built on
`material` — that is where `ColorScheme` and the dialog come from.) Vanilla
Flutter works out of the box via `ValueListenableBuilder` — zero
dependencies. Bloc/Riverpod/Provider/GetX wiring is a ~15-line
`ValueListenable` wrapper in your app (bring your own package) — see
[best practices](doc/best_practices.md) for the pattern.

And it is testable headless: `HintController.test()` (a
`@visibleForTesting` factory) runs the whole machine — wait-for-target,
timeouts, typo validation, diagnostics — with no overlay at all, which is
how the tour flow tests drive it (`test/helpers/tour_harness.dart`).
Headless vs full-fidelity, and the two-frame rule:
[best practices §20](doc/best_practices.md#20-testing--headless-first).

## Features

**Tour control**

- `start/next/previous/goTo/skip/finish`; safe variants
  `tryStart/restart/tryShowHint` + `isIdle` — no manual guards before starting
- Wait-for-target for deferred and lazy-loaded widgets, with timeout + diagnosis
- Missing targets: `HintMissingTargetPolicy.skipStep` (the tour default)
  skips an absent target with a `timeout` diagnosis and continues the tour;
  short/`Duration.zero` per-step `stepTimeout` for conditionally-absent targets
- Scoped controllers: `scopePrefix` isolates tabs/split-view sharing one
  registry (foreign ids neither activate steps nor false-fire typo candidates)
- `disableBackButton` owns the Android back button while a tour is active;
  Skip auto-hides on the last step of a multi-step tour (Done does the
  same); a single-step hint keeps no action row at all

**Rendering**

- CompositedTransform tooltip + scrim — follows scroll/layout/animation for free
- Smart positioning: auto-flip to the side with room, keep-in-safe-area,
  and a tail (arrow) tying the tooltip to its target — a hint never lands
  half off-screen or on top of the control it points at
- Multi-target steps: several elements spotlighted at once, the tooltip
  avoiding the other spotlighted targets
- Multi-content: several tooltips around one target, guaranteed not to
  overlap each other or the targets
- Optional blur scrim and pulsing ring (theme options; the default stays a
  plain dim — the lightest thing to render)
- Focus shapes (rectangle/circle/rounded) + padding (including negative
  shrink), and scroll-into-view: an offscreen target is brought on screen
  with its step
- Animation is the tooltip's job: no built-in entry animation — a custom
  `tooltipBuilder` animates its own entry (the engine still places it);
  honor `MediaQuery.disableAnimations` inline for reduce-motion
- Tap regions: tap-on-target vs tap-on-overlay with per-step callbacks and
  tap position; scroll-through — the page scrolls under an active tour

**Content & reuse**

- Versioned hints (`HintStore`): show once per app version —
  configure the store once (`Hintful.configure(store: ...)`) and call
  `startOnce(tour, mark:)` (default `HintMarkPolicy.onAnyExit`; the version
  gate lives on `HintTour.minShowVersion`) or `shouldShow`/`markShown` by
  hand; with no store configured, a session `InMemoryHintStore` keeps
  show-once working for this run only. `CallbackHintStore(read:, write:)`
  is the three-line path over your storage; `hintful_prefs` ships a
  ready-made shared_preferences store
- "Want a tour?" pre-dialog (`showHintTourOffer`, own `HintTourOfferLabels`):
  copy themed via `HintTheme.tourOfferLabels` (or per-call `labels:`),
  declines persist per page or globally; gates return
  `HintTourOfferResult.alreadyShown`, accept while busy returns `busy`;
  an accepted tour is recorded per `mark:` (`onAnyExit` by default), the
  tour stays reachable from other entry points
- `withHint` sugar (`child.withHint('id')`) and target-level
  `focusShape`/`focusPadding` — the shape lives on the widget, a step
  overrides only the exception
- Per-step lifecycle hooks: `onStepEnter`/`onStepExit` (async) bracket a
  step visit — serialized, exit of the old step runs before enter of the
  new one; analytics and app reactions
- One content slot type (`HintStepContent`) for strings + l10n
  builders; one tap behavior per region (`targetTap`/`overlayTap`:
  advance / ignore / custom)

## Public contract

The only supported import is `package:hintful/hintful.dart`. Deep imports
(`package:hintful/engine/...`, `package:hintful/widgets/...`) are not part of
the API — implementation lives under `lib/src/` and is reachable only through
this barrel (explicit `show` lists). The exported surface: tour data
(`HintStep`/`HintTour`/`HintTooltip`/`HintStepContent`/`HintTapBehavior` +
`TooltipPosition`/`FocusShape`/`HintMissingTargetPolicy`),
registry (`HintTargetRegistry`), machine states
(`HintState`/`HintIdle`/`HintWaiting`/`HintActive`), controller
(`HintController`, `HintActions`, `HintTooltipContext`), diagnostics
(`HintDiagnosticsHandler`/`HintSkipEvent`/`HintSkipReason`), theme/labels
(`HintTheme`/`HintTooltipLabels`), widgets (`HintTarget`/`withHint`,
`DefaultTooltip`, `showHintTourOffer` + offer labels/result),
config (`Hintful`), store (`HintStore`/`InMemoryHintStore`/
`CallbackHintStore`/`HintMarkPolicy`).

Every rule behind the bullets above — what to do, what not to, and why — lives
in [best practices](doc/best_practices.md#index), one decision per section:
targets and shape (§1), `isIdle` vs `tryStart` (§5), versions (§6), multi-target
and multi-content (§14–15), taps (§16), motion (§17), navigation (§18),
server-driven tours (§19), testing (§20).

## Server-driven tours

No extra dependency — `HintTour.fromJson`/`toJson` with your own HTTP client:
```dart
final body = await http.get(
  Uri.parse('https://cdn.example.com/tours/onboarding'),
); // your client — http, dio, HttpClient, …
final tour = HintTour.fromJson(jsonDecode(body.body) as Map<String, dynamic>);
await controller.start(tour);
```
Keep a bundled fallback tour for the offline / failed-fetch case.

The wire format carries copy, order, timing and layout of **known** targets —
builders and callbacks stay in code, so a server cannot introduce a target that
isn't in the shipped build. Payload rules, validation and the offline fallback:
[best practices §19](doc/best_practices.md#19-server-driven-tours--what-json-can-and-cannot-carry).

## Getting started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  hintful: ^1.0.0
```

```dart
import 'package:hintful/hintful.dart';
```

Requires Dart ≥ 3.0 / Flutter ≥ 3.10 — that floor comes from three things
hintful leans on: sealed machine states, `CompositedTransform` +
`LayerLink.leaderSize`, and `ThemeExtension`.

See `example/` for working demos of every feature above — shaped holes,
blur/pulse styles, custom animated tooltips, JSON tours, tap regions, the  offer dialog, and the versioned intro.

## Documentation

- [`doc/best_practices.md`](doc/best_practices.md#index) — the decisions that keep
  tours findable and hard to break, one per section, with the code to copy;
- [`doc/faq.md`](doc/faq.md) — "my hint didn't show", `GlobalKey`, `tryStart`,
  text scale, taps, multi-target vs multi-content, testing,
  server-driven tours and the offer dialog;
- [`CHANGELOG.md`](CHANGELOG.md) — what changed across 0.x → 1.0.0;
- [`benchmark/README.md`](benchmark/README.md) — how the numbers under
  [Performance](#performance) are recorded.

## Verifying

For contributors and agents — the same commands CI runs:

```bash
# package root
flutter pub get && flutter analyze && flutter test
dart format --set-exit-if-changed .
flutter pub publish --dry-run

# example/
flutter pub get && flutter analyze && flutter test

# benchmark/
flutter pub get && flutter analyze && flutter test bench/
```

MIT licensed.

---

<!-- bench:start -->
## Performance

One scene, three solutions: the contract scenarios S1–S6 on a profile Android emulator plus the host size builds (S7). Values are the recorded goldens in `benchmarks.json` (refs `android` / `android-scv` / `android-tcm`). Methodology: `benchmark/README.md`; `benchmark/compare` hosts the rival drivers.

| Metric | hintful | showcaseview | tutorial_coach_mark |
|---|---|---|---|
| Idle tree diff (S1) | 4 | 2 | 3 |
| Idle resources (S1r) | 0 | 0 | 0 |
| Show latency (S2) | 108 ms | 163 ms | 774 ms |
| Update latency (S3) | 159 ms | 304 ms | 1418 ms |
| Active-step heap (S5) | 42 KB | 65 KB | 94 KB |
| Heap retained after hide (S6) | -59 B | -325 B | -91 B |
| Native AOT size | 76 KB | n/a | n/a |
| Web startup bundle delta | 53 KB | n/a | n/a |

**n/a** = not applicable for this solution. Scroll coupling (S4) is a two-sided in-scenario assert, not a numeric row: hintful re-anchors its content to the target under programmatic scroll on-device, while showcaseview and tutorial_coach_mark do not (their overlays consume pointer input). The idle-resources row (S1r) is declared on-device via `idleClasses` — 0 means the solution holds no live control-plane instances while idle. The size rows are hintful-only because the rival scenes were never shipped as size targets.

**Trend history:** [charts](https://fellmonkey.github.io/hintful/bench/)

![hintful benchmark metrics](doc/hint_metrics.png)

_Recorded 2026-09-12 20:43 UTC. Regenerate: dispatch the `bench-record` workflow with `record`._
<!-- bench:end -->

