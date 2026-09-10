# FAQ

---

### 1. My hint didn't show — why?

Check the debug log:

```
[hintful] intro step 2 not shown: timeout (target 'stats') — target 'stats' did not appear within 0:00:03.000000
[hintful] intro step 1 not shown: unknown-target (target 'statz') — closest: stats
```

- **`timeout`** — target never appeared within `stepTimeout` (default 3s). Check the `targetId` and that the widget is mounted. For conditional widgets, use `waitTimeout: Duration.zero` + `skipStep`.
- **`unknown-target`** — typo. The log shows the closest `targetId`s.
- **`userSkipped`** — user tapped Skip or pressed Esc.

In release, `diagnostics: null` (zero cost).

---

### 2. Do I need a `GlobalKey`?

No. `HintTarget(id: 'filters')` registers by `id` — the `LayerLink` lives inside. `GlobalKey` breaks on scroll and rebuilds.

```dart
ChoiceChip(...).withHint('filters') // not Showcase(key: GlobalKey())
```

---

### 3. `isIdle` vs `tryStart` — when to use which?

- **`isIdle`** — for UI only: `onPressed: isIdle ? () => start(tour) : null`.
- **`tryStart`** — atomic guard for `start` (returns `false` if busy, no assert).

```dart
// ❌ race
if (controller.isIdle) await controller.start(tour);

// ✅ no race
if (!await controller.tryStart(tour)) return;
```

`start` is `Future` for future server `fetch`; for local tours you may fire-and-forget.

---

### 4. `targetRect` without `HintTarget` — when do I need `overlay`?

When no `HintTarget` is mounted, the engine has nowhere to get an `OverlayState`.

```dart
final key = GlobalKey<OverlayState>();
MaterialApp(home: Overlay(key: key, initialEntries: [...]));

// rect-based tour
HintController(overlayHostBuilder: defaultOverlayHost(overlay: () => key.currentState))
```

Otherwise you don't need `overlay` — the engine finds the root overlay from the first target.

---

### 5. Text overflows at `2.0` scale?

The tooltip caps height and scrolls. Write shorter instead: **8 words for title, 20 for description**. Need more? Use `moreTooltips` or a second step.

Test with `MediaQuery.textScalerOf(context).scale(2.0)` — hintful handles it, but short copy never needs to scroll.

---
