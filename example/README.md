# hintful_example

Demo app for the **hintful** package — every engine feature you can see
with your own eyes, plus the versioned-intro pattern.

## What the demo shows

The AppBar has **Show tour** (the versioned intro), **Show hint** and
**Toggle theme**; everything else lives in the two demo cards.

| Feature | How to see it |
|---|---|
| Tour flow, wait-for-target, deferred target, auto-scroll | **Show tour** (AppBar) — the versioned intro: 4 steps, the "Summary" card appears 600 ms after step 3 activates (deferred target), and the tour is `autoScroll: true` |
| Zero-config single tip | **Show hint** (AppBar) — one `HintStep`, no `HintTour` ceremony |
| Light/dark theming | **Toggle theme** (AppBar) — tooltips inherit the `ColorScheme` through `HintTheme` |
| Versioned hints (`shouldShow` + `minVersion`) | **Versioned intro** card — "Bump version" re-shows the intro, "Reset store" clears it; the store is `shared_preferences`-backed |
| Blur / pulse scrim options | **Visual demos** card — pick a style chip (Plain / Blur / Pulse / Blur + Pulse); it applies to every tour |
| Multi-target steps (several holes at once) | **Multi-target** |
| Multi-content (several tooltips around one target) | **Multi-content** |
| Tap regions (target vs overlay, tap position) | **Tap regions** — tap the button / the dark area, watch the snackbar |
| Enum-typed steps + "Want a tour?" pre-dialog | **Offer tour** — the tour comes from `HintTour.fromEnum`; the dialog offers it once and declines persist ("Apply to all pages") |
| Server-driven shape (`HintTour.fromJson`) | **JSON** — steps parsed from a map run like declared ones |
| l10n, target-level shape, `withHint` | **L10n** — copy through `titleBuilder`, `withHint('filter-all')`, a circular target; its first step sets `autoScroll: true` to bring that row in |
| Spotlight shapes | **Circle / Rounded / Neg pad / Rect** — `focusShape`, negative `focusPadding`, and a `targetRect` step with no widget at all |
| Entry-animation rungs | **Sprung** (the preset bounce) and **Custom** (a `tooltipBuilder` with its own `TweenAnimationBuilder`) |
| Step lifecycle hooks | **Hooks** — `onBeforeAction`/`onAfterAction` fire around the step |
| Per-step scroll | **Step scroll** — the offscreen `entry-5` step sets `autoScroll: true`, the first step of that tour does not |

## Layout

The demo is split so each layer stays readable:

- `main.dart` — the app shell: controller, light/dark + scrim-style
  theming, the versioned-intro store gate, the demo launchers and the
  per-tour app reactions (only the intro reveals the deferred summary card).
- `home_screen.dart` — `HintHomeScreen`: registers all tour targets
  (`fab`, filters, the deferred `stats` card, workout rows) and hosts the
  demo cards (style chips + one button per feature).
- `demo_tours.dart` — the tour definitions behind every button in the table
  above.
- `shared_prefs_hint_store.dart` — a `shared_preferences`-backed
  `HintStore` (the library core stays dependency-free; this is the
  pattern for real apps).

## Running

```bash
flutter run
```

## Tests

`flutter test` — 12 smoke tests: every tour in the table above walks end to end,
including the deferred target's waiting phase and the versioned-intro cycle
(show → gated → bump → reset), plus `showHint`, light/dark, taps, both
offer-dialog paths and the custom `tooltipBuilder`.
