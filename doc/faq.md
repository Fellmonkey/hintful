# FAQ

---

### 1. My hint didn't show — why?

Check the debug log:

```
[hintful] intro step 2 not shown: timeout (target 'stats') — target 'stats' did not appear within 0:00:03.000000
[hintful] intro step 1 not shown: unknown-target (target 'statz') — closest: stats
```

- **`timeout`** — the target never appeared within `stepTimeout` (default 3s). Check the `targetId` and that the widget is mounted. For conditional widgets, use `stepTimeout: Duration.zero` + `skipStep`.
- **`unknown-target`** — typo. The log shows the closest `targetId`s (when an
  unregistered id counts as a typo and when it is instead a deferred target
  the tour should wait for: [§12](#12-correct-id-yet-the-step-reports-unknown-target)).
- **`user-skipped`** — the user tapped Skip or pressed Esc.
- **`overlay-unavailable`** — the engine could not mount its render host: no `OverlayState` was reachable and no mounted target could supply one. It happens when a tour starts before any `HintTarget` has mounted — let the first target build first.

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

### 3. `isIdle` vs `tryShowTour` — when to use which?

- **`isIdle`** — for UI only: `onPressed: isIdle ? () => showTour(tour) : null`.
- **`tryShowTour`** — atomic guard for `showTour` (returns `false` if busy **or if nothing was shown** — a tour `showTour` declined to run; no assert).

```dart
// ❌ race
if (controller.isIdle) await controller.showTour(tour);

// ✅ no race
if (!await controller.tryShowTour(tour)) return;
```

`showTour` returns a `Future` (so a server `fetch` can feed it later); for local tours you may fire-and-forget.

---

### 4. Do I ever need to hand the engine an `Overlay`?

No. The engine captures the root overlay from the first mounted `HintTarget`
— zero configuration.

---

### 5. Text overflows at `2.0` scale?

The tooltip caps height and scrolls. Write shorter instead: **8 words for title, 20 for description**. Need more? Use `additionalTooltips` or a second step.

Test with `MediaQuery.textScalerOf(context).scale(2.0)` — hintful handles it, but short copy never needs to scroll.

---

### 6. I tapped the button and the tour took the tap

The step owns the tap: its layer sits above the page, so the spotlighted widget
never sees its own `onPressed` while a step is active.

Hand the action to the tour:

```dart
HintStep(
  targetId: 'addSet',
  targetTap: HintTapBehavior.custom((ctx, details) {
    logSet();            // the real action
    ctx.actions.next();  // then move on
  }),
)
```

A callback **replaces** the default advance for its region, so call
`ctx.actions.next()` when the step should continue.

Full section: [best practices §15](best_practices.md#15-taps--who-owns-the-gesture).

---

### 7. Two widgets, one idea — `additionalTargets` or `additionalTooltips`?

`additionalTargets` widens the **spotlight** (one tooltip, several holes);
`additionalTooltips` adds **tooltips** around one hole:

```dart
// one tooltip, two holes
HintStep(targetId: 'filter-all', additionalTargets: ['filter-daily'], content: HintStepContent(title: 'Two filters, one job'))

// one hole, two tooltips
HintStep(targetId: 'stats', content: HintStepContent(title: 'Your week'), additionalTooltips: [
  HintAdditionalTooltip(position: TooltipPosition.left, content: HintStepContent(title: 'Volume', description: '12.4 t')),
])
```

The step waits for **all** its `additionalTargets` before it activates, and extras are
informational (no buttons) — set their `position` explicitly.

More: [best practices §13](best_practices.md#13-multi-target--several-things-one-story)
and [§14](best_practices.md#14-multi-content--a-second-tooltip).

---

### 8. How do I test a tour?

Headless first — no overlay, the whole machine. Record diagnostics with your own
callback (a plain function — pass it directly or tear off a method):

```dart
final reasons = <HintSkipReason>[];
final controller = HintController.test(
  registry: HintTargetRegistry(), // your own, not the app singleton
  diagnostics: (e) => reasons.add(e.reason),
); // headless — the whole machine, no render mechanics

await controller.showTour(tour);
expect(reasons, [HintSkipReason.timeout]);
controller.dispose();
```

A custom `registry:` must be shared: hand the same instance to every
`HintTarget` in the scene, or the controller watches an empty registry
and every step dies as `timeout`.

A typo'd `targetId` is an **assert in debug** — catch it with
`expectLater(controller.showTour(tour), throwsAssertionError)`.

For full-fidelity tests (scrim, tooltip copy, taps) build a real scene the way
the package's `test/helpers/tour_harness.dart` does — and pump **twice** after
`showTour`: frame 1 draws the scrim, frame 2 the tooltip.

More: [best practices §19](best_practices.md#19-testing--headless-first).

---

### 9. Can tours come from the server?

Yes, with no HTTP dependency added to the package:

```dart
final body = await http.get(
  Uri.parse('https://cdn.example.com/tours/onboarding'),
); // your client — http, dio, HttpClient, …
final tour = HintTour.fromJson(jsonDecode(body.body) as Map<String, dynamic>);
```

The payload can reword, reorder, retime and restyle a tour. It **cannot** carry
builders or callbacks (`titleBuilder`, `descriptionBuilder`, `tooltipBuilder`,
`HintTapBehavior.custom`, the hooks) and it cannot invent targets: every
`targetId` must exist in the build the user is running.

So treat it as untrusted: an unknown enum value (`position: "middle"`) falls back
to the field's default and is reported through `onWarning` (and a debug print),
while an unknown `targetId` is a typo assert in debug and a skipped step in
release. Always keep a bundled fallback for the offline case.

More: [best practices §18](best_practices.md#18-server-driven-tours--what-json-can-and-cannot-carry).

---

### 10. Show the tour, or offer it first?

Offer it when the tour is optional and the screen has other jobs:

```dart
await showHintTourOffer(
  context: context,
  controller: controller, // reads the store configured via Hintful.configure
  tour: AppTours.settings(minShowVersion: appVersion), // versioned factory
  pageId: 'settings',
);
```

It skips the dialog when the tour already ran for `tour.minShowVersion`
(`versionGated`), remembers a decline per page (or globally with the
"Apply to all pages" checkbox), and counts a barrier dismissal as a decline.
Accepting starts the tour and records the shown-state **on any exit**
(`HintMarkPolicy.onAnyExit`, the default — finish/skip/timeout all count).
Pass `HintMarkPolicy.onFinish` or `HintMarkPolicy.manual` if your policy
differs — see [best practices §6](best_practices.md#6-once-per-version--hintstore).

Offer from one entry point per page, and keep the tour reachable after a decline
(settings, help menu): that is why the decline keys are namespaced apart from the
tour's own key.

More: [best practices §20](best_practices.md#20-the-offer-dialog--want-a-tour).

---

### 11. Does positioning work in RTL?

Yes. `TooltipPosition.auto` (the default) picks the side with the most free
space and never reads the text direction — an RTL screen needs no
configuration. `left`/`right` are **physical** sides of the target, not
`start`/`end`; the enum is closed in 1.x, so a screen that needs the logical
side maps it at the call site:

```dart
final rtl = Directionality.of(context) == TextDirection.rtl;
final step = HintStep(
  targetId: 'save',
  content: HintStepContent(title: 'Save'),
  position: rtl ? TooltipPosition.right : TooltipPosition.left,
);
```

The hole, scrim and tail are direction-agnostic, and the tooltip body is your
own widget tree — it inherits `Directionality` like the rest of the app.

---

### 12. Correct id, yet the step reports `unknown-target`?

Classification runs once at tour start and compares each unregistered id with
the registry (see [§1](#1-my-hint-didnt-show--why)):

- **within edit distance 2** of a registered id (`statz` vs `stats`) — a
  typo: assertion in debug, the step is **skipped in release** (waiting for
  an id that will never mount is pointless);
- **no close match** — a legitimate deferred target: the tour waits for it;
- **differs from a registered id only in digits** (`row-2` vs a registered
  `row-1`) — deferred too: numeric suffixes are naming, not typos.

The sharp edge is the first rule, and it applies at tour start — when a
deferred target is still unregistered. An id that *reads* like a registered
one within two edits is taken for a typo: `filter-all-2` next to a registered
`filter-all` is distance 2, and it is not digits-only (the hyphen is a real
difference on top of the digit), so that step is skipped in release. A
numbered **sibling** is fine (`row-2` beside `row-1`); a numbered
**extension of the registered name itself** is not. When in doubt, give the
deferred id a purely numeric suffix (`filter-all2`) or more than two edits of
distance from every registered id.
