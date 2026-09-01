# hintful

**Hints & onboarding tours for Flutter.** Spotlight targets, tooltips, coach marks,
guided walkthroughs — a single source of truth for teaching users your product.

`hintful` is a domain-driven **hint tokenizer**: you wrap one widget in
`HintTarget`, describe what to show in a `HintTour`, and let the engine render,
reposition and remember it — without a single hand-written overlay, scroll math
or duplicated per-screen styling.

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
| Tied to Bloc/Riverpod/… | **Framework-agnostic core** — vanilla `ValueListenable<HintState>`, no state-management imports (adapters are roadmap) |
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
    HintStep(targetId: 'exerciseSelector', tooltipBuilder: _buildTooltip),
    HintStep(targetId: 'addSet',        tooltipBuilder: _buildTooltip),
  ],
);

// 3. Show it once
controller.start(introTour);
```

No `GlobalKey`, no `OverlayEntry`, no `ScrollController`, no manual position.
That's it.

## Zero-config, then total control

`hintful` works with a single `HintTarget(id: ..., title: ..., desc: ...)` and a
default theme out of the box (or `showHint` for one tip without a `HintTour`). When
you need more, the API grows through an explicit "ladder of customization" —
`HintTheme` styles → a fully custom tooltip through `tooltipBuilder` — each
step optional. Your design system, your call.

## Diagnosis over mystery

When a hint doesn't show, you'll know why in one log line:

```
[hintful] statsIntro not shown: target-not-rendered (step 2 → 'statsPeriodSelector')
```

Not "it just didn't appear." If you typo a `targetId`, `hintful` tells you loudly in
debug — with the closest candidates.

## Accessibility, on by default

`hintful` treats accessibility as a default, not an option:

- **Screen readers**: every step is announced as "Step N of M: <title>".
- **Keyboard**: Tab/Shift+Tab move forward/back, Enter = next, Esc = skip;
  the tour manages focus and returns it to the element you were on before
  it started.
- **Reduce motion**: with the system setting on, transitions are instant.
- **Text scale**: the tooltip fits on screen at 2× text scale (content
  scrolls instead of overflowing).
- **Contrast**: the default theme meets WCAG AA (4.5:1) for text and
  buttons, in light and dark.

All of it is covered by tests, not just intentions.

## Works anywhere

The core is framework-agnostic by construction: it imports only `dart:ui` +
`flutter/widgets`, no state-management package. Vanilla Flutter works out of the
box via `ValueListenableBuilder` — zero dependencies. Thin adapters for
Bloc/Riverpod/Provider/GetX are on the roadmap.

## Features

- Registry-based targets (no `GlobalKey`) with self-cancellation in `dispose`
- CompositedTransform tooltip + scrim — follows scroll/layout/animation for free
- Wait-for-target for deferred and lazy-loaded widgets, with timeout + diagnosis
- ThemeExtension design-system integration, light/dark by default
- Smart positioning: auto-flip to the side with room, keep-in-safe-area,
  and a tail (arrow) tying the tooltip to its target
- Programmatic controller: `start/next/previous/goTo/skip/finish`;
  tap-overlay = next; keyboard (Tab/Shift+Tab/Enter, Esc = skip); optional
  `disableBackButton`; one-line `showHint` for a single tip
- Accessibility on by default: screen-reader step announcements, keyboard
  navigation, reduce-motion, fits at 2× text scale, WCAG AA contrast,
  focus restored after a tour
- Zero-idle cost: zero engine widgets in the tree until a tour actually starts
- Hot-reload friendly; debug diagnosis of every failed show, with closest-id
  candidates when a `targetId` is a typo

Roadmap: versioned hints, server-driven tours, migration guides.

## Getting started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  hintful: ^0.2.0
```

```dart
import 'package:hintful/hintful.dart';
```

See `example/` for a complete tour — 4 steps with a scrollable list, a
deferred target that appears mid-tour, light/dark switching and `showHint`.

---

### Status

Stage 0 (early engine) is complete: registry, state machine with tests, tour
controller, CompositedTransform overlay with scrim hole that follows the target
for free, auto-flip tooltip placement, theme integration, DX diagnosis and an
end-to-end example. Stage 1 is in progress: tour navigation
(`previous`/`goTo`, `disableBackButton`), smart positioning (keep-in-safe-area,
tooltip tail) and accessibility (reduce-motion, 2× text scale, WCAG AA
contrast, focus restore) are done; the Bloc adapter ships as a separate
`hintful_bloc` package. Versioned hints, server-driven tours and migration
guides are next.