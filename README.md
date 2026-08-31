# hintful

**Hints & onboarding tours for Flutter.** Spotlight targets, tooltips, coach marks,
guided walkthroughs — a single source of truth for teaching users your product.

`hintful` is a domain-driven **hint tokenizer**: you wrap one widget in
`ShowcaseTarget`, describe what to show in a `TourSpec`, and let the engine render,
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
| References to widget contexts | **Registry by id** — `ShowcaseTarget(id: 'filters')` registers/unregisters itself; nothing to unmount |
| "Wait until the widget is built" by hand | **Wait-for-target** — a tour waits for a deferred target instead of dying |
| Per-hint hard-coded styling | **ThemeExtension** — hint inherits your design system, light and dark, from `Theme.of` |
| Tied to Bloc/Riverpod/… | **Framework-agnostic** — vanilla `ValueListenable<TourState>` in the core, thin adapters for Bloc/Riverpod/Provider/GetX |
| Overlay mounted even when idle | **Zero-idle cost** — zero engine widgets in the tree until a tour actually starts |

## What you write

```dart
// 1. Wrap the thing you want to explain
ShowcaseTarget(
  id: 'exerciseSelector',
  child: ExerciseSelector(),
)

// 2. Declare the tour — data, not widgets
final introTour = TourSpec(
  id: 'intro',
  steps: [
    StepSpec(targetId: 'exerciseSelector', tooltipBuilder: _buildTooltip),
    StepSpec(targetId: 'addSet',        tooltipBuilder: _buildTooltip),
  ],
);

// 3. Show it once
controller.start(introTour);
```

No `GlobalKey`, no `OverlayEntry`, no `ScrollController`, no manual position.
That's it.

## Zero-config, then total control

`hintful` works with a single `ShowcaseTarget(id: ..., title: ..., desc: ...)` and a
default theme out of the box. When you need more, the API grows through an explicit
"ladder of customization" — tooltip styles → button builders → a fully custom
tooltip widget → a custom overlay → painter hooks — each step optional, each
overridable per step. Your design system, your state management, your call.

## Diagnosis over mystery

When a hint doesn't show, you'll know why in one log line:

```
[hintful] statsIntro not shown: target-not-rendered (step 2 → 'statsPeriodSelector')
```

Not "it just didn't appear." If you typo a `targetId`, `hintful` tells you loudly in
debug — with the closest candidates.

## Works anywhere

Vanilla Flutter, or the adapter for whatever you use:

| State management | Adapter |
|---|---|
| Vanilla Flutter | `ValueListenableBuilder` — no dependency at all |
| Bloc | `ShowcaseCubit` |
| Riverpod | `NotifierProvider` |
| Provider | `ChangeNotifierProvider` |
| GetX | `GetxController` |

## Features

- Registry-based targets (no `GlobalKey`) with self-cancellation in `dispose`
- CompositedTransform tooltip + scrim — follows scroll/layout/animation for free
- Wait-for-target for deferred and lazy-loaded widgets
- ThemeExtension design-system integration, light/dark by default
- Accessibility-first: semantics, keyboard (Tab/Esc/Enter), reduce-motion, text-scale
- Smart positioning: auto-flip, keep-in-safe-area, never covers the target
- Versioned hints: "what's new in 2.3.0", shown once per feature version
- Programmatic controller: `start/next/previous/goTo/skip/finish`
- Tap-target / tap-overlay, tooltip tail, blur backdrop, optional pulse
- Hot-reload friendly; debug diagnosis of every failed show

## Getting started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  hintful: ^0.1.0
```

```dart
import 'package:hintful/hintful.dart';
```

See `example/` for a complete minimal tour, and `docs/` for the design
rationale and the migration guide from `showcaseview`.

---

### Status

Early but architecturally complete: Engine (registry + state machine +
CompositedTransform overlay + scrim). Roadmap: deployment, drop-in layer for
`showcaseview`, 6 per-library migration guides, benchmark contract, accessibility
and server-driven tours hardening.