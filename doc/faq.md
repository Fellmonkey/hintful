# FAQ

---

### 1. My hint didn't show — why?

Check the debug log:

```
[hintful] intro step 2 not shown: timeout (target 'stats') — target 'stats' did not appear within 0:00:03.000000
[hintful] intro step 1 not shown: unknown-target (target 'statz') — closest: stats
```

- **`timeout`** — the target never appeared within `stepTimeout` (default 3s). Check the `targetId` and that the widget is mounted. For conditional widgets, use `waitTimeout: Duration.zero` + `skipStep`.
- **`unknown-target`** — typo. The log shows the closest `targetId`s.
- **`user-skipped`** — the user tapped Skip or pressed Esc.
- **`target-not-rendered`** — the engine could not mount its render host: no `OverlayState` was reachable and no mounted target could supply one. It happens on zero-target tours (`targetRect` only) — pass `overlay:` to `defaultOverlayHost`.

A spotlighted target that **vanishes** mid-step is deliberately not reported: the
step returns to the waiting phase and re-arms its timeout, so a permanent loss
shows up as `timeout`.

In release, `diagnostics: null` (zero cost). More:
[best practices §12](best_practices.md#12-diagnostics--trust-the-log).

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

`start` returns a `Future` (so a server `fetch` can feed it later); for local tours you may fire-and-forget.

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

### 6. I tapped the button and the tour took the tap

The step owns the tap: its layer sits above the page, so the spotlighted widget
never sees its own `onPressed` while a step is active.

Hand the action to the tour:

```dart
HintStep(
  targetId: 'addSet',
  onTapTarget: (ctx, details) {
    logSet();            // the real action
    ctx.actions.next();  // then move on
  },
)
```

A callback **replaces** the default advance for its region, so call
`ctx.actions.next()` when the step should continue.

Full section: [best practices §16](best_practices.md#16-taps--who-owns-the-gesture).

---

### 7. Two widgets, one idea — `moreTargets` or `moreTooltips`?

`moreTargets` widens the **spotlight** (one tooltip, several holes);
`moreTooltips` adds **tooltips** around one hole:

```dart
// one tooltip, two holes
HintStep(targetId: 'filter-all', moreTargets: ['filter-daily'], title: 'Two filters, one job')

// one hole, two tooltips
HintStep(targetId: 'stats', title: 'Your week', moreTooltips: [
  HintTooltip(position: TooltipPosition.left, title: 'Volume', description: '12.4 t'),
])
```

The step waits for **all** its `moreTargets` before it activates, and extras are
informational (no buttons) — set their `position` explicitly.

More: [best practices §14](best_practices.md#14-multi-target--several-things-one-story)
and [§15](best_practices.md#15-multi-content--a-second-tooltip).

---

### 8. How do I test a tour?

Headless first — no overlay, the whole machine. Record diagnostics with your own
handler:

```dart
class Recorder implements HintDiagnosticsHandler {
  final reasons = <HintSkipReason>[];
  @override
  void onHintSkipped(String tourId, int stepIndex, String targetId,
      HintSkipReason reason, String detail) => reasons.add(reason);
}

final recorder = Recorder();
final controller = HintController(
  registry: HintTargetRegistry(), // your own, not the app singleton
  diagnostics: recorder,
  // no overlayHostBuilder → headless
);

await controller.start(tour);
expect(recorder.reasons, [HintSkipReason.timeout]);
controller.dispose();
```

A typo'd `targetId` is an **assert in debug** — catch it with
`expectLater(controller.start(tour), throwsAssertionError)`.

For full-fidelity tests (scrim, tooltip copy, taps) build a real scene the way
the package's `test/helpers/tour_harness.dart` does — and pump **twice** after
`start`: frame 1 draws the scrim, frame 2 the tooltip.

More: [best practices §20](best_practices.md#20-testing--headless-first).

---

### 9. Can tours come from the server?

Yes, with no HTTP dependency added to the package:

```dart
final factory = FetcherHintTourFactory(
  baseUrl: 'https://cdn.example.com/tours',
  fetcher: (uri) async => (await http.get(uri)).body, // your client
);
final tour = await factory.fetch('onboarding');
```

The payload can reword, reorder, retime and restyle a tour. It **cannot** carry
builders or callbacks (`titleBuilder`, `descriptionBuilder`, `tooltipBuilder`,
`onTapTarget`, the hooks) and it cannot invent targets: every `targetId` must
exist in the build the user is running.

So treat it as untrusted: an unknown enum value (`position: "middle"`) falls back
to the field's default and is reported through `onWarning` (and a debug print),
while an unknown `targetId` is a typo assert in debug and a skipped step in
release. Always keep a bundled fallback for the offline case.

More: [best practices §19](best_practices.md#19-server-driven-tours--what-json-can-and-cannot-carry).

---

### 10. Show the tour, or offer it first?

Offer it when the tour is optional and the screen has other jobs:

```dart
await showHintTourOffer(
  context: context,
  controller: controller,
  tour: AppTours.settings(),
  store: store,
  pageId: 'settings',
  minVersion: appVersion,
);
```

It skips the dialog when the tour already ran for `minVersion`, remembers a
decline per page (or globally with the "Apply to all pages" checkbox), and
counts a barrier dismissal as a decline. Accepting starts the tour; recording the
shown-state stays yours, **on exit** —
[best practices §6](best_practices.md#6-once-per-version--hintstore).

Offer from one entry point per page, and keep the tour reachable after a decline
(settings, help menu): that is why the decline keys are namespaced apart from the
tour's own key.

More: [best practices §21](best_practices.md#21-the-offer-dialog--want-a-tour).

---
