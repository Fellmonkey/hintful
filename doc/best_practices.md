# Best practices

Keep tours easy to find, easy to change, and hard to break. Each rule below is one decision — with the code to copy and the reason it matters.

---

## 0. Architecture — one file owns all tours

Put every tour in `lib/app_tours.dart` as plain data — no `BuildContext`, no widgets.

```dart
// app_tours.dart
abstract class AppTours {
  static HintTour intro() => HintTour(id: 'intro', autoScroll: true, steps: [
    HintStep(targetId: 'fab', titleBuilder: (c) => c.l10n.introFab),
    HintStep(targetId: 'list', title: 'List'),
  ]);

  static HintTour settings() => HintTour(id: 'settings', steps: [...]);
}
```

Tours become searchable, diffable in PRs, and serializable (`toJson`/`fromJson` for server-driven). Scattering `HintStep`s across screens hides duplicate `targetId`s until runtime — `duplicateTargetIds` then fires late.

> **Rule:** `AppTours` owns *what* to show. Screens own *where* (`withHint` / `HintTarget`). App owns *when* (`HintStore` + `controller.tryStart`). Never keep tours in `State`.

---

## 1. Targets — shape lives on the widget

A round avatar should not repeat `focusShape: circle` in every step.

```dart
CircleAvatar(...).withHint(
  'avatar',
  focusShape: FocusShape.circle,
  focusPadding: 6,
);

// step stays clean
HintStep(targetId: 'avatar', title: 'Profile')
```

`step.shape ?? target.shape ?? rectangle` — the step wins only for the exception. Same for `focusPadding` (default `4.0`).

---

## 2. Tours — let the compiler help

```dart
enum IntroStep { filters, list }

HintTour intro = HintTour.fromEnum(
  id: 'intro',
  values: IntroStep.values,
  stepFor: (s) => switch (s) {
    IntroStep.filters => HintStep(targetId: 'filters', title: 'Filters'),
    IntroStep.list    => HintStep(targetId: 'list', title: 'List'),
  },
);
```

Add a value to `IntroStep` without updating `stepFor` → compile error, not a silent missing tooltip.

---

## 3. Text — use builders for localization

Don't thread `BuildContext` through `AppTours`:

```dart
HintStep(
  titleBuilder: (c) => AppLocalizations.of(c)!.introTitle,
  descriptionBuilder: (c) => AppLocalizations.of(c)!.introBody,
)
```

In the overlay `effectiveTitle(context)` prefers the builder, falls back to `title`, and never hits `toJson`. Your `AppTours` file stays `const`-friendly until the overlay provides `context`.

---

## 4. Copy — hints are UI, not docs

A spotlight can teach in 5 seconds or annoy in 5 seconds. Write for the second.

**Lead with outcome, not feature:**

```dart
// ❌ feature
HintStep(title: 'Filters', description: 'Filter by muscle, equipment.')

// ✅ outcome — what I get
HintStep(title: 'Find it in seconds', description: 'Filter by muscle or equipment — no scrolling.')
```

**Be specific:**

| Vague | Specific |
|---|---|
| Save time | Log a set in one tap |
| Many workouts | 12 workouts |
| Improve workflow | Filters → Pick → Log |

**One idea per step:**

```dart
// ❌ two ideas in one
HintStep(title: 'Filters and summary', description: 'Filter and see stats.')

// ✅ two steps, each one job
HintStep(targetId: 'filters', title: 'Narrow it down')
HintStep(targetId: 'stats', title: 'See the total')
```

**Match the CTA to the promise:**

Default `Next`/`Done`/`Skip` come from `HintTooltipLabels` — localize once in `HintTheme`. For a custom `tooltipBuilder`, use the same verb as the title:

```dart
titleBuilder: (c) => c.l10n.hintAddSetTitle, // "Log your first set"
// button: "Log it" — not "Next"
```

**Keep it short:** 8 words for title, 20 for description. Need more? Use `moreTooltips` or a second step. Test at `2.0` text scale — hintful caps and scrolls, but short copy never needs it.

---

## 5. When to show — separate UI state from the guard

- `controller.isIdle` — for UI only (disable the Start button).
- `controller.tryStart(tour)` — atomic guard for `start` (returns `false` if busy, no assert).

```dart
IconButton(onPressed: controller.isIdle ? () => controller.start(tour) : null)

// fire-and-forget without a race
if (!await controller.tryStart(tour)) return; // busy
```

`start` is `Future` for future server `fetch`; for local tours you may fire-and-forget.

---

## 6. Once per version — `HintStore`

```dart
if (!store.shouldShow('intro', minVersion: '1.2.0')) return;
await controller.start(tour);
store.markShown('intro', '1.2.0');
```

`InMemoryHintStore` ships in core. `SharedPreferences` lives outside the barrel — import only if you need persistence. `compareVersions` handles `1.10.0` correctly.

---

## 7. Offscreen — opt-in auto-scroll

Offscreen targets render as **full dim, no hole** until scrolled into view. That's honest, not frozen.

```dart
HintTour(id: 'long', autoScroll: true, steps: [...]) // whole tour
HintStep(targetId: 'entry-5', autoScroll: true)       // one step
```

Default `false` — the engine never moves content unless you ask. `ensureVisible` runs only if `!screen.contains(rect)`.

---

## 8. Scroll — don't fight it

Hole rides the compositor, tooltip follows via `ScrollPosition` delta in the same frame. No `ScrollController` math on your side.

> Previously a `scrollDelta`-high gap flickered at the bottom. Now global `Positioned.fill` + `hole += -delta`.

---
## 9. One tip — use `showHint`

One tip is not a tour:

```dart
controller.showHint(HintStep(targetId: 'fab', title: 'Swipe to delete'));
```

No `Done`/`Skip` row when `totalSteps == 1`. The hint closes by tap or keyboard and looks distinct from a tour.

---
 — don't fight it

Hole rides the compositor, tooltip follows via `ScrollPosition` delta in the same frame. No `ScrollController` math on your side.

> Previously a `scrollDelta`-high gap flickered at the bottom. Now global `Positioned.fill` + `hole += -delta`.

---

## 10. Shapes — negative padding is safe

```dart
HintTarget(..., focusPadding: -4) // hole shrinks inside the widget
```

Over-shrunk (`isEmpty`) → full dim, never a crash. Corner radius is clamped to `shortestSide/2`.

---

## 11. Custom — `tooltipBuilder` is the escape hatch

`sprung` is the only preset. Everything else is your builder:

```dart
HintStep(
  tooltipBuilder: (c, step, ctx) => TweenAnimationBuilder(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: Duration(milliseconds: 400),
    builder: (_, t, child) => Opacity(opacity: t, child: child),
    child: DefaultTooltip(step: step, ctx: ctx),
  ),
)
```

Check `MediaQuery.disableAnimations` inside for `reduceMotion`.

---

## 12. Diagnostics — trust the log

```
[hintful] intro step 2 not shown: timeout (target 'stats') — target 'stats' did not appear within 0:00:03.000000
```

Typo → closest `targetId` candidates in debug, `diagnostics: null` in release (0 cost).

---

## 13. No widget — `targetRect`

Spotlight at coordinates, no `HintTarget`:

```dart
HintStep(targetRect: Rect.fromLTWH(100, 300, 120, 40), title: 'Here')
```

Needs an explicit `overlay: () => key.currentState` when no targets are mounted. Enters `Active` immediately.

