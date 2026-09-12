# Best practices

Keep tours easy to find, easy to change, and hard to break. Each rule below is one decision — with the code to copy and the reason it matters.

## Index

**Structure** — [0 Architecture](#0-architecture--one-file-owns-all-tours) · [1 Targets](#1-targets--shape-lives-on-the-widget) · [2 Tours](#2-tours--let-the-compiler-help) · [3 Text](#3-text--use-builders-for-localization)

**Entry points** — [5 isIdle vs tryStart](#5-when-to-show--separate-ui-state-from-the-guard) · [6 Once per version](#6-once-per-version--hintstore) · [21 The offer dialog](#21-the-offer-dialog--want-a-tour)

**Copy & look** — [4 Copy](#4-copy--hints-are-ui-not-docs) · [10 Shapes](#10-shapes--negative-padding-is-safe) · [11 Custom tooltip](#11-custom--tooltipbuilder-is-the-escape-hatch) · [17 Motion](#17-motion--three-rungs-one-duty)

**On screen** — [7 Offscreen](#7-offscreen--opt-in-auto-scroll) · [8 Scroll](#8-scroll--dont-fight-it) · [9 One tip](#9-one-tip--use-showhint) · [13 targetRect](#13-targetrect--spotlight-without-a-widget) · [14 Multi-target](#14-multi-target--several-things-one-story) · [15 Multi-content](#15-multi-content--a-second-tooltip) · [16 Taps](#16-taps--who-owns-the-gesture) · [18 Navigation](#18-navigation--the-tour-and-the-back-button)

**Diagnostics & delivery** — [12 Diagnostics](#12-diagnostics--trust-the-log) · [19 Server-driven tours](#19-server-driven-tours--what-json-can-and-cannot-carry) · [20 Testing](#20-testing--headless-first)

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

Where the controller lives: create it once at app level, pass it down, and
`dispose()` it with its owner. It holds the registry listener, the wait timer and
the overlay host — skip the `dispose()` and you leak all three. One controller
per screen (or per tab) is fine; the one-tour-at-a-time rule is per controller.

Tabs and split views share `HintTargetRegistry.defaultInstance`, so a scoped-off
controller sees the *other* screen's ids: a step can activate on a target that is
not on screen. Give each screen a `scopePrefix` and prefix its ids with it —
foreign ids then neither activate steps nor show up as typo candidates:

```dart
// the greenhouse tab
final controller = HintController(
  scopePrefix: 'greenhouse-',
  overlayHostBuilder: defaultOverlayHost(),
);

HintTarget(id: 'greenhouse-addBed', child: AddBedButton())
HintStep(targetId: 'greenhouse-addBed', title: 'Add a bed')
```

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

`step.shape ?? target.shape ?? rectangle` — the step wins only for the exception. Same for `focusPadding` (default `4.0`, logical px). On a multi-target step (`moreTargets`) the **primary** target decides for every hole: shape and padding are read from the first registration, extras do not get their own.

Two more target rules:

- ids are the contract between `AppTours` and the screens — keep them stable, screen-scoped and unique. A duplicate id on two mounted widgets is "last registration wins" (with a warning), and a renamed id silently turns the step into a diagnosed typo;
- `HintTarget(semanticsLabel: ...)` labels the spotlighted widget itself for the screen reader — set it when the spotlight sits on an icon-only control.

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

`fromEnum` guards the step list; the rest of the tour contract is worth setting
deliberately:

- `stepTimeout` (default 3 s) — how long a step waits for its target; per-step `waitTimeout` and `missingTargetPolicy: skipStep` for targets that exist only sometimes (pair it with a short or `Duration.zero` timeout).
- `disableBackButton` — the tour owns Android back while it runs.
- `tour.id` is not decoration: it is the `HintStore` key and the id in every diagnostics line, so renaming a tour resets its "already shown" history.

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

A spotlight can teach in 5 seconds or annoy for 5 seconds. Aim for the first.

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

`start` returns a `Future` (so a server `fetch` can feed it later); for local tours you may fire-and-forget.

---

## 6. Once per version — `HintStore`

`shouldShow` before, `markShown` after — and "after" is the trap: `start` returns
as soon as the tour is **seeded** (step 1 is on screen), not when the tour ends.
Marking straight after `start` records a tour the user may have skipped one frame
later.

Gate it, then record it on exit:

```dart
Future<void> startIntro() async {
  if (!store.shouldShow('intro', minVersion: appVersion)) return;
  if (!await controller.tryStart(intro)) return; // busy — nothing was shown
  _introRunning = true; // your own flag
}

// on exit: the controller is idle again
controller.state.addListener(() {
  if (_introRunning && controller.currentState.isIdle) {
    _introRunning = false;
    store.markShown('intro', appVersion);
  }
});
```

Marking on start ("the user saw step 1") is defensible too — the point is to pick
one definition and keep it in the entry point, never scattered across screens.

Key and version rules:

- the key is yours; the hintful convention is `tour.id`, and renaming the tour starts its shown-history from zero;
- the offer dialog keeps its own namespaced decline keys (`offer:<tourId>`, `offer:<tourId>@<pageId>`) — a decline does not suppress the tour from other entry points;
- `minVersion` is the version the hint targets ("new in 1.2.0") and `compareVersions` orders `1.10.0 > 1.9.0` correctly; `clear()` is a debug/test tool — the production "show again" is a version bump.

`InMemoryHintStore` ships in core: the right store for tests and the reference
implementation of the rules above. A persistent store — `SharedPreferences`, a
backend — lives outside the barrel; implement `HintStore` and nothing else
changes.

---

## 7. Offscreen — opt-in auto-scroll

Offscreen targets render as **full dim, no hole** until scrolled into view. That's honest, not frozen.

```dart
HintTour(id: 'long', autoScroll: true, steps: [...]) // whole tour
HintStep(targetId: 'entry-5', autoScroll: true)       // one step
```

Default `false` — the engine never moves content unless you ask. Turn it on per
tour for long screens and override it per step where the movement would be
jarring.

Three caveats, in the order they usually bite:

- only the **primary** target of a step is scrolled — `moreTargets` extras stay where they are;
- a target with no `Scrollable` ancestor is not scrolled at all: autoScroll goes through `Scrollable.ensureVisible` on the target's context and silently does nothing without one;
- it moves only when the target is not fully on screen (both corners inside the viewport → nothing happens), with a 350 ms `easeInOut`.

---

## 8. Scroll — don't fight it

Hole rides the compositor, tooltip follows via `ScrollPosition` delta in the same frame. No `ScrollController` math on your side.

What that asks of your app — nothing, plus two don'ts:

- **don't lock scrolling** while a tour runs: the page keeps living under the scrim (scroll-through is deliberate — the user can reach the next target themselves) and hole and tooltip follow it;
- **don't unmount the spotlighted widget** mid-step. If it disappears (list recycling, a collapsed tab, a `PageView` rebuilding its page) the step returns to the waiting phase and re-arms its timeout instead of aborting: transient unmounts recover, a permanent loss ends in a `timeout` diagnosis. `targetRect` steps are exempt — their spotlight is static.

Nested and horizontal scrollables are fine: the engine follows the target's own
resolved position, not one `ScrollController`.

---

## 9. One tip — use `showHint`

One tip is not a tour:

```dart
controller.showHint(HintStep(targetId: 'fab', title: 'Swipe to delete'));
```

No `Done`/`Skip` row when `totalSteps == 1`. The hint closes by tap or keyboard and looks distinct from a tour.

---

## 10. Shapes — negative padding is safe

```dart
HintTarget(..., focusPadding: -4) // hole shrinks inside the widget
HintStep(targetId: 'avatar', focusShape: FocusShape.circle)
```

`FocusShape.rectangle` (default) / `roundedRect` / `circle`, and `focusPadding`
(default `4.0`, logical px) inflates the target rect — negative shrinks it.
Over-shrunk (`isEmpty`) → full dim, never a crash. Corner radius is clamped to
`shortestSide/2`.

Shape and padding come from the primary target on a multi-target step — see §1.

---

## 11. Custom — `tooltipBuilder` is the escape hatch

`easeOut` and `sprung` are the presets (§17). Everything else is your builder:

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

The contract:

- the builder receives `(BuildContext, HintStep, HintTooltipContext)`; `ctx` is `actions` (`next`/`previous`/`skip`/`finish`) plus `stepIndex`, `totalSteps` and `isLast` — that is what "2/5" and "Done instead of Next" are rendered from, no controller needed;
- the engine still **places** it: keep-in-safe-area, avoid-the-spotlighted-target and the slot layout apply to whatever you return, and the tail is wrapped around it too (theme `showTail`, on by default) — turn that off in `HintTheme` if your tooltip draws its own;
- the engine renders **no buttons** for a custom tooltip: the action row belongs to `DefaultTooltip`, so calling back into `DefaultTooltip(step:, ctx:)` is the cheap way to keep the default look and animate around it;
- the screen-reader announcement ("Step N of M: …") also lives in `DefaultTooltip`; a fully custom tooltip should announce itself — `HintTooltipLabels.announce(...)` produces the same string;
- reduce motion is on you, not on the engine — the shared helper for it is in
  §17.

---

## 12. Diagnostics — trust the log

```
[hintful] intro step 2 not shown: timeout (target 'stats') — target 'stats' did not appear within 0:00:03.000000
```

Reasons are typed (`HintSkipReason`): `timeout`, `unknown-target`,
`user-skipped`, and `target-not-rendered` (no overlay could be found or captured).
A target that vanishes mid-step is *not* reported — the step goes back to waiting
and a permanent loss surfaces as `timeout`.

`DebugPrintDiagnostics` is the default, and the controller only attaches it in
debug builds: in release `diagnostics` is `null` and costs nothing. Wire your own
for analytics or a dev panel — same contract, any number of handlers:

```dart
HintController(diagnostics: const AnalyticsDiagnostics());

class AnalyticsDiagnostics implements HintDiagnosticsHandler {
  const AnalyticsDiagnostics();

  @override
  void onHintSkipped(String tourId, int stepIndex, String targetId,
      HintSkipReason reason, String detail) {
    analytics.log('hint_skipped', {
      'tour': tourId,
      'step': stepIndex,
      'target': targetId,
      'reason': reason.label,
    });
  }
}
```

Two behaviours to know before trusting a green local run: a typo'd `targetId` is
an **assert in debug** (loud, with the closest candidates) and a **skipped step in
release** — the tour continues; a timed-out step follows `missingTargetPolicy`
(`abortTour` by default, `skipStep` to carry on).

---

## 13. `targetRect` — spotlight without a widget

Spotlight at coordinates, no `HintTarget`:

```dart
HintStep(targetRect: Rect.fromLTWH(100, 300, 120, 40), title: 'Here')
```

The rect is in **overlay coordinates** (logical px — the space the tooltip is laid
out in): derive it from a render box or a known layout, do not hand-tune it from
a screenshot. What this mode is and is not:

- it is **static** — no follower, no position watching: the hole does not follow scroll or layout changes, so the app must not move the content under it;
- `moreTooltips` and the pulse ring are not rendered (they need live targets); the primary tooltip, the tail, `focusShape`/`focusPadding` and tap regions all work;
- the step enters `Active` immediately — there is nothing to wait for, so `waitTimeout` and `missingTargetPolicy` are irrelevant here.

Needs an explicit overlay provider when no targets are mounted — there is
nothing to capture the root overlay from:

```dart
final overlayKey = GlobalKey<OverlayState>();
HintController(
  overlayHostBuilder: defaultOverlayHost(overlay: () => overlayKey.currentState),
);
```

Otherwise the engine finds the root overlay from the first registered target.

---

## 14. Multi-target — several things, one story

Sometimes one idea spans two widgets: both filters, a label and its switch, a
value and its unit.

```dart
HintStep(
  targetId: 'filter-all',
  moreTargets: ['filter-daily'], // one hole each, ONE tooltip
  title: 'Two filters, one job',
)
```

Rules that matter:

- the step activates only when **all** its targets are mounted — a deferred extra holds the whole step in the waiting phase, and the timeout names every missing target rather than just the first;
- one tooltip, anchored to the primary `targetId` — that is also the target `autoScroll` scrolls (§7) and the one whose shape/padding applies to every hole (§1);
- placement avoids **all** spotlighted targets, so the tooltip never covers the second hole;
- an id cannot repeat across the steps of one tour (`duplicateTargetIds` asserts on `start`) — spotlight both chips in the *same* step instead of giving them a step each;
- a tap inside **any** hole counts as the target region (§16).

Keep it to two, maybe three targets. Past that the step stops reading as one
idea and starts looking like a bug.

---

## 15. Multi-content — a second tooltip

`moreTargets` widens the spotlight; `moreTooltips` adds tooltips around **one**
target — a side note, a measurement, a "why".

```dart
HintStep(
  targetId: 'stats',
  title: 'Your week',
  moreTooltips: [
    HintTooltip(
      position: TooltipPosition.left,
      title: 'Volume',
      description: '12.4 t',
    ),
  ],
)
```

- set `position` explicitly on an extra: `auto` re-picks by free space and can fight the primary for the same side;
- extras are informational by default (`DefaultTooltip(showActions: false)`, no buttons) — give one a `tooltipBuilder` if a slot needs its own action;
- the engine guarantees slots do not overlap each other or the spotlighted targets, so you position nothing;
- extras carry the tail too (pointing at the primary hole) and are **not** rendered in `targetRect` steps — see §13.

---

## 16. Taps — who owns the gesture

The step's tap layer sits above the page, so a tap inside a spotlight (the
"target region") or on the scrim (the "overlay region") goes to the tour, **not**
to the widget underneath: a spotlighted button does not run its own `onPressed`
while the step is active.

By default both regions advance. Replace a region's behavior with a callback, or
turn it off — a callback takes over the advance, so move on yourself with
`ctx.actions.next()`:

```dart
HintStep(
  targetId: 'deleteSwipe',
  tapOnOverlay: false,      // a stray scrim tap must not advance
  onTapTarget: (ctx, details) {
    analytics.log('tapped_target', details.globalPosition);
    doTheRealAction();
    ctx.actions.next();     // move on when it makes sense
  },
)
```

When to deviate:

- **critical steps** (irreversible actions, permission prompts): `tapOnOverlay: false` plus an explicit `onTapTarget`/button — a tap anywhere must not glide past them;
- **the user must actually use the control** (log the first set): do it from `onTapTarget` — the widget itself will not receive the tap;
- **drags stay free**: the tap layer is translucent, so scrolling and scroll-through are unaffected (§8).

---

## 17. Motion — three rungs, one duty

The animation ladder, from cheapest to richest:

1. **none** (default): leave `transitionCurve` unset — the tooltip appears. Right for most product hints;
2. **a preset**: `HintCurve.easeOut` — the quiet one (fade + scale 0.96 → 1, `easeOut`, 200 ms); `HintCurve.sprung` — the bounce (scale 0.8 → 1, `elasticOut`, 800 ms) for a step meant to delight. Both take `transitionDuration` as an override;
3. **your builder**: anything else lives in `tooltipBuilder` (§11).

The duty: the engine honors the system reduce-motion setting for its presets, and
`hintTransitionDuration(...)` is the same check, exported for your builder — it
returns `Duration.zero` when the user asked for less motion:

```dart
final duration = hintTransitionDuration(
  MediaQuery.of(context),
  const Duration(milliseconds: 400),
);
if (duration == Duration.zero) return card; // reduce motion: no animation
```

Two habits: keep hint transitions short (a few hundred ms — a hint is not a page
transition), and prefer no animation over a wrong one — `sprung` on a destructive
step reads as playful at exactly the wrong moment.

---

## 18. Navigation — the tour and the back button

Set `disableBackButton: true` when a tour must survive the system back gesture
(Android back / predictive back): the engine consumes the pop while the tour
runs. Two limits worth knowing:

- it intercepts the **system** pop (`didPopRoute`), not a programmatic `Navigator.pop()` in your own code — pop a route yourself and the tour is simply left behind;
- it is per tour, so decide at tour level: a settings tour opened from a modal probably should not own back.

Leaving the screen mid-tour: the targets unmount, the step returns to waiting
(§8) and eventually times out. When you know the screen is going away, end the
tour yourself:

```dart
@override
void dispose() {
  controller.skip(); // no-op when idle
  super.dispose();
}
```

`finish()` and `skip()` both end the tour and both are no-ops while idle; the
difference is the diagnosis (`user-skipped` vs no diagnostic at all), so use
`skip()` when a human aborted and `finish()` for a normal programmatic end.

---

## 19. Server-driven tours — what JSON can and cannot carry

`HintTour.fromJson`/`toJson` plus `FetcherHintTourFactory` (your own client, no
HTTP dependency in the package) let a server reword, reorder and restyle a tour
you already shipped:

```dart
final factory = FetcherHintTourFactory(
  baseUrl: 'https://cdn.example.com/tours',
  fetcher: (uri) async => (await http.get(uri)).body,
);

HintTour tour;
try {
  tour = await factory.fetch('onboarding');
} catch (_) {
  tour = AppTours.onboarding(); // bundled fallback — never strand the user
}
await controller.start(tour);
```

What the wire format carries: `id`, steps with `targetId`/`moreTargets`, titles
and descriptions, `position`, `moreTooltips`, `stepTimeoutMs`/`waitTimeoutMs`,
`showSkip`, the missing-target policy, `tapOn*`, shapes/padding, `autoScroll`,
`transitionCurve` and `targetRect`.

What it **cannot** carry: builders and callbacks. `titleBuilder`,
`descriptionBuilder`, `tooltipBuilder`, `onTapTarget` and the lifecycle hooks are
code-side only. So a server rewrites the copy and the order of **known** targets
— it cannot introduce targets that do not exist in the binary the user is
running.

Practical rules:

- keep the tour id stable — it is the `HintStore` key and the diagnostics id;
- treat the payload as untrusted: an unknown enum value (`position: "middle"`)
  falls back to the field's default and is reported (a debug print plus the
  `onWarning` callback on `HintTour.fromJson` / `HintStep.fromJson` /
  `HintTooltip.fromJson` / `FetcherHintTourFactory`), and an unknown `targetId`
  is a typo assert in debug / a skipped step in release;
- always keep a bundled fallback — never strand the user on a failed fetch.

`InMemoryHintTourFactory` is the same interface for tests and previews.

---

## 20. Testing — headless first

The controller does not need a UI: with `overlayHostBuilder: null` the whole
machine runs without an overlay — waiting, timeouts, typo validation, policies,
diagnostics — so a tour flow is a plain unit test:

```dart
final controller = HintController(
  registry: HintTargetRegistry(), // your own, never the app singleton
  diagnostics: recorder,
  // no overlayHostBuilder → headless
);

await controller.start(tour);                       // typo → assertion in debug
expect(await controller.tryStart(tour), isFalse);   // busy: atomic guard
controller.next();
expect(controller.currentState, isA<HintWaiting>());
controller.dispose();
```

Notes:

- pass your own `HintTargetRegistry` so a test never depends on the app's targets (or pollutes them);
- assert on diagnostics with a recording `HintDiagnosticsHandler`, not by capturing `debugPrint` output;
- a typo'd `targetId` is designed for `expectLater(controller.start(tour), throwsAssertionError)` — `start` returns a `Future` so the failure surfaces in the test instead of inside someone's build;
- keep test tours on a short/`Duration.zero` `stepTimeout`, and remember timers must be pumped or a missing target fails after the real 3 s;
- `dispose()` every controller (it is idempotent) — otherwise the registry listener and the timer outlive the test.

For full-fidelity tests (scrim, tooltip copy, taps, positioning) build a real
scene — `MaterialApp` + `HintTarget`s + `defaultOverlayHost()` — the way the
package's own `test/helpers/tour_harness.dart` does, and remember the two-frame
rule: `start` renders the scrim on frame 1 and the tooltip on frame 2, so pump
twice before asserting the tooltip.

---

## 21. The offer dialog — "Want a tour?"

`showHintTourOffer` is the ask-first wrapper: a pre-dialog with an "Apply to all
pages" checkbox that starts the tour on accept.

```dart
final result = await showHintTourOffer(
  context: context,
  controller: controller,
  tour: AppTours.settings(),
  store: store,
  pageId: 'settings',     // the page this offer belongs to
  minVersion: appVersion, // already ran this version → no dialog
  labels: HintTourOfferLabels(title: l10n.offerTitle),
);
```

What it handles for you: no dialog when the tour already ran for `minVersion`, a
decline remembered per page (and globally when the checkbox is on) under
namespaced keys, and a barrier dismissal counted as a decline — "not now" must
not nag. Accepting calls `controller.start(tour)`; recording the shown-state
stays yours, on exit, exactly as in §6.

Two rules: one offer per page entry point (offer from three buttons and the
dialog appears where the user least expects it), and keep the tour reachable
after a decline (settings, help menu) — the namespaced decline keys in §6 are
what make that possible. `HintTourOfferLabels` carries the copy
(title, body, accept, later, checkbox) and `HintTourOfferResult` tells you which
branch was taken if you want to log it.

