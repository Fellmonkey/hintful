# hintful_example

Demo app for the **hintful** package — every engine feature you can see
with your own eyes, plus the versioned-intro pattern (N4).

## What the demo shows

| Feature | How to see it |
|---|---|
| Tour flow, wait-for-target, scroll-into-view | **Show tour** (AppBar) — the versioned intro: 4 steps, the "Summary" card appears 600 ms after step 3 activates (deferred target) |
| Zero-config single tip | **Show hint** (AppBar) — one `HintStep`, no `HintTour` ceremony |
| Light/dark theming | **Toggle theme** (AppBar) — tooltips inherit the `ColorScheme` through `HintTheme` |
| Versioned hints (`shouldShow` + `minVersion`) | **Versioned intro** card — "Bump version" re-shows the intro, "Reset store" clears it |
| Blur / pulse scrim options | **Visual demos** card — pick a style chip; it applies to every tour |
| Multi-target steps (several holes at once) | **Multi-target** button |
| Multi-content (several tooltips around one target) | **Multi-content** button |
| Tap regions (target vs overlay, tap position) | **Tap regions** button — tap the button / the dark area, watch the snackbar |
| Enum-typed steps + "Want a tour?" pre-dialog | **Offer tour** button — the tour is built from an enum (`HintTour.fromEnum`); the dialog offers it once, declines persist ("Apply to all pages" checkbox) |

## Layout

The demo is split into three files so each layer stays readable:

- `main.dart` — the app shell: controller, light/dark + scrim-style
  theming, the versioned-intro store gate, per-tour app reactions
  (only the intro reveals the deferred summary card).
- `home_screen.dart` — `HintHomeScreen`: registers all tour targets
  (`fab`, filters, the deferred `stats` card, workout rows) and hosts
  the demo cards.
- `demo_tours.dart` — the tour definitions: intro, multi-target,
  multi-content, tap-regions.
- `shared_prefs_hint_store.dart` — a `shared_preferences`-backed
  `HintStore` (the library core stays dependency-free; this is the
  pattern for real apps).

## Running

```bash
flutter run
```

## Tests

`flutter test` — smoke tests walk every tour end to end (including the
deferred target), the versioned-intro cycle, light/dark, tap regions and
the pulse style.
