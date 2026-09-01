# Changelog

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