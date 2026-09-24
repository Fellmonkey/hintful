# Best practices

Keep tours easy to find, easy to change, and hard to break. Each rule below is one decision — with the code to copy and the reason it matters.

## Index

**Structure** — [0 Architecture](#0-architecture--one-file-owns-all-tours) · [1 Targets](#1-targets--shape-lives-on-the-widget) · [2 Tours](#2-tours--let-the-compiler-help) · [3 Text](#3-text--use-builders-for-localization)

**Entry points** — [5 isIdle vs tryStart](#5-when-to-show--separate-ui-state-from-the-guard) · [6 Once per version](#6-once-per-version--hintstore) · [20 The offer dialog](#20-the-offer-dialog--want-a-tour)

**Copy & look** — [4 Copy](#4-copy--hints-are-ui-not-docs) · [10 Shapes](#10-shapes--negative-padding-is-safe) · [11 Custom tooltip](#11-custom--tooltipbuilder-is-the-escape-hatch) · [16 Motion](#16-motion--animate-it-yourself)

**On screen** — [7 Offscreen](#7-offscreen--opt-in-auto-scroll) · [8 Scroll](#8-scroll--dont-fight-it) · [9 One tip](#9-one-tip--use-showhint) · [13 Multi-target](#13-multi-target--several-things-one-story) · [14 Multi-content](#14-multi-content--a-second-tooltip) · [15 Taps](#15-taps--who-owns-the-gesture) · [17 Navigation](#17-navigation--the-tour-and-the-back-button)

**Diagnostics & delivery** — [12 Diagnostics](#12-diagnostics--trust-the-log) · [18 Server-driven tours](#18-server-driven-tours--what-json-can-and-cannot-carry) · [19 Testing](#19-testing--headless-first)

---

## 0. Architecture — one file owns all tours

Put every tour in `lib/app_tours.dart` as plain data — no `BuildContext`, no widgets.

```dart
// app_tours.dart
abstract class AppTours {
  static HintTour intro() => HintTour(id: 'intro', autoScroll: true, steps: [
    HintStep(targetId: 'fab', content: HintStepContent(titleBuilder: (c) => c.l10n.introFab)),
    HintStep(targetId: 'list', content: HintStepContent(title: 'List')),
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
);

HintTarget(id: 'greenhouse-addBed', child: AddBedButton())
HintStep(targetId: 'greenhouse-addBed', content: HintStepContent(title: 'Add a bed'))
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
HintStep(targetId: 'avatar', content: HintStepContent(title: 'Profile'))
```

`step.shape ?? target.shape ?? rectangle` — the step wins only for the exception. Same for `focusPadding` (default `4.0`, logical px). On a multi-target step (`additionalTargets`) the **primary** target decides for every hole: shape and padding are read from the first registration, extras do not get their own.

Two more target rules:

- ids are the contract between `AppTours` and the screens — keep them stable, screen-scoped and unique. A duplicate id on two mounted widgets is "last registration wins" (with a warning), and a renamed id silently turns the step into a diagnosed typo;
- `HintTarget(semanticsLabel: ...)` labels the spotlighted widget itself for the screen reader — set it when the spotlight sits on an icon-only control.

---

## 2. Tours — let the compiler help

Keep the step list as plain data — searchable, diffable in PRs, serializable:

```dart
HintTour intro = HintTour(
  id: 'intro',
  steps: [
    HintStep(targetId: 'filters', content: HintStepContent(title: 'Filters')),
    HintStep(targetId: 'list', content: HintStepContent(title: 'List')),
  ],
);
```

Prefer enums over string ids in your own file (`IntroStep.filters` feeding a
private `_stepFor` helper) to keep ids and steps in sync — the tour itself
takes a plain steps list.

The rest of the tour contract is worth setting deliberately:

- `stepTimeout` (default 3 s) — how long a step waits for its target; the
  tour-level `missingTargetPolicy` (default `skipStep`) for targets that
  exist only sometimes (pair with a short or `Duration.zero` per-step timeout).
- `disableBackButton` — the tour owns Android back while it runs.
- `tour.id` is not decoration: it is the `HintStore` key and the id in every diagnostics line, so renaming a tour resets its "already shown" history.

---

## 3. Text — use builders for localization

Don't thread `BuildContext` through `AppTours`:

```dart
HintStep(
  content: HintStepContent(
    titleBuilder: (c) => AppLocalizations.of(c)!.introTitle,
    descriptionBuilder: (c) => AppLocalizations.of(c)!.introBody,
  ),
)
```

In the overlay `effectiveTitle(context)` prefers the builder, falls back to `title`, and never hits `toJson`. Your `AppTours` file stays `const`-friendly until the overlay provides `context`.

---

## 4. Copy — hints are UI, not docs

A spotlight can teach in 5 seconds or annoy for 5 seconds. Aim for the first.

**Lead with outcome, not feature:**

```dart
// ❌ feature
HintStep(content: HintStepContent(title: 'Filters', description: 'Filter by muscle, equipment.'))

// ✅ outcome — what I get
HintStep(content: HintStepContent(title: 'Find it in seconds', description: 'Filter by muscle or equipment — no scrolling.'))
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
HintStep(content: HintStepContent(title: 'Filters and summary', description: 'Filter and see stats.'))

// ✅ two steps, each one job
HintStep(targetId: 'filters', content: HintStepContent(title: 'Narrow it down'))
HintStep(targetId: 'stats', content: HintStepContent(title: 'See the total'))
```

**Match the CTA to the promise:**

Default `Next`/`Done`/`Skip` come from `HintTooltipLabels` — localize once in `HintTheme`. For a custom `tooltipBuilder`, use the same verb as the title:

```dart
titleBuilder: (c) => c.l10n.hintAddSetTitle, // "Log your first set"
// (inside HintStepContent) button: "Log it" — not "Next"
```

**Keep it short:** 8 words for title, 20 for description. Need more? Use `additionalTooltips` or a second step. Test at `2.0` text scale — hintful caps and scrolls, but short copy never needs it.

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

**Preferred:** `startOnce` — gate + start + mark under a policy in one call.
Configure the store once app-wide (`Hintful.configure(store: store)`); there
is no per-call store and no controller-level field. With no store
configured, a session `InMemoryHintStore`
takes over (debug prints a one-time warning) — show-once works for this run
only; configure a persistent store for real once-per-version semantics
(`Hintful.store` exposes what was configured):

```dart
Hintful.configure(store: store); // once, at wiring

final started = await controller.startOnce(
  AppTours.intro(appVersion), // HintTour(..., minShowVersion: appVersion)
  // mark: HintMarkPolicy.onAnyExit, // the default — see the policies below
  version: appVersion, // what gets recorded (defaults to minShowVersion)
);
if (!started) return; // already shown for this version, or busy
```

`HintMarkPolicy` (closed in 1.x):

- `onAnyExit` (default) — `markShown` runs on **any exit after the tour
  started**: finish (Done / last step), skip or timeout all count as "the
  user has seen it". Retires the hand-rolled idle-listener pattern below.
- `onFinish` — `markShown` runs **only on finish** (Done / last step). Skip
  and timeout abort *without* marking — the tour may show again next
  launch. Use when only a completed tour counts as "seen".
- `manual` — never marks; the app owns the shown-state entirely.

Prefer `startOnce` when a standard policy fits. For anything else (mark on
first frame, mark a different key) roll your own:

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

The trap with the manual path: `start` returns as soon as the tour is
**seeded** (step 1 is on screen), not when it ends — marking straight after
`start` records a tour the user may have skipped one frame later. Prefer
`HintMarkPolicy.onAnyExit`, which is exactly this listener, built in.

Key and version rules:

- the key is yours; the hintful convention is `tour.id`, and renaming the tour starts its shown-history from zero;
- the offer dialog keeps its own namespaced decline keys (`offer:<tourId>`, `offer:<tourId>@<pageId>`) — a decline does not suppress the tour from other entry points;
- `minVersion` is the version the hint targets ("new in 1.2.0"); versions compare segment-wise (`1.10.0 > 1.9.0`); `clear()` is a debug/test tool of a concrete store — the production "show again" is a version bump.

`InMemoryHintStore` ships in core: the right store for tests and the reference
implementation of the rules above. For persistent storage the short path is
`CallbackHintStore(read:, write:)` — three lines over `SharedPreferences` or
your own key-value layer — and the `hintful_prefs` companion package ships a
ready-made `SharedPreferencesHintStore` (namespaced keys, a `clear()` dev
tool, a public `compareVersions`). The app owns the storage; the core package
stays dependency-free. A full class (`implements HintStore`) is only needed
when you want richer behavior — the two-member contract is frozen for 1.x.

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

- only the **primary** target of a step is scrolled — `additionalTargets` extras stay where they are;
- a target with no `Scrollable` ancestor is not scrolled at all: autoScroll goes through `Scrollable.ensureVisible` on the target's context and silently does nothing without one;
- it moves only when the target is not fully on screen (both corners inside the viewport → nothing happens), with a 350 ms `easeInOut`.

---

## 8. Scroll — don't fight it

Hole rides the compositor, tooltip follows via `ScrollPosition` delta in the same frame. No `ScrollController` math on your side.

What that asks of your app — nothing, plus two don'ts:

- **don't lock scrolling** while a tour runs: the page keeps living under the scrim (scroll-through is deliberate — the user can reach the next target themselves) and hole and tooltip follow it;
- **don't unmount the spotlighted widget** mid-step. If it disappears (list recycling, a collapsed tab, a `PageView` rebuilding its page) the step returns to the waiting phase and re-arms its timeout instead of aborting: transient unmounts recover, a permanent loss ends in a `timeout` diagnosis.

Nested and horizontal scrollables are fine: the engine follows the target's own
resolved position, not one `ScrollController`.

---

## 9. One tip — use `showHint`

One tip is not a tour:

```dart
controller.showHint(HintStep(targetId: 'fab', content: HintStepContent(title: 'Swipe to delete')));
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
- reduce motion is on you, not on the engine — check `MediaQuery.disableAnimations`
  and render instantly when it is set (§16).

---

## 12. Diagnostics — trust the log

```
[hintful] intro step 2 not shown: timeout (target 'stats') — target 'stats' did not appear within 0:00:03.000000
```

Reasons are typed (`HintSkipReason`): `timeout`, `unknown-target`,
`user-skipped`, and `overlay-unavailable` (no overlay could be found or captured).
A target that vanishes mid-step is *not* reported — the step goes back to waiting
and a permanent loss surfaces as `timeout`.

`diagnostics:` is a plain function (`typedef HintDiagnosticsHandler`) — one
callback per controller. Debug builds **always print** the formatted line
(`[hintful] …`) first, then invoke your callback; in release only your
callback runs (or nothing — zero cost):

```dart
HintController(
  diagnostics: (e) => analytics.log('hint_skipped', {
    'tour': e.tourId,
    'step': e.stepIndex,
    'target': e.targetId,
    'reason': e.reason.label, // stable string — safe for string-keyed sinks
    'detail': e.detail,
  }),
);
```

Two behaviours to know before trusting a green local run: a typo'd `targetId` is
an **assert in debug** (loud, with the closest candidates) and a **skipped step in
release** — the tour continues; a timed-out step follows the tour's
`missingTargetPolicy` (`skipStep` by default — the tour continues;
`abortTour` to stop).

---

## 13. Multi-target — several things, one story

Sometimes one idea spans two widgets: both filters, a label and its switch, a
value and its unit.

```dart
HintStep(
  targetId: 'filter-all',
  additionalTargets: ['filter-daily'], // one hole each, ONE tooltip
  content: HintStepContent(title: 'Two filters, one job'),
)
```

Rules that matter:

- the step activates only when **all** its targets are mounted — a deferred extra holds the whole step in the waiting phase, and the timeout names every missing target rather than just the first;
- one tooltip, anchored to the primary `targetId` — that is also the target `autoScroll` scrolls (§7) and the one whose shape/padding applies to every hole (§1);
- placement avoids **all** spotlighted targets, so the tooltip never covers the second hole;
- an id cannot repeat across the steps of one tour (`duplicateTargetIds` asserts on `start`) — spotlight both chips in the *same* step instead of giving them a step each;
- a tap inside **any** hole counts as the target region (§15).

Keep it to two, maybe three targets. Past that the step stops reading as one
idea and starts looking like a bug.

---

## 14. Multi-content — a second tooltip

`additionalTargets` widens the spotlight; `additionalTooltips` adds tooltips around **one**
target — a side note, a measurement, a "why".

```dart
HintStep(
  targetId: 'stats',
  content: HintStepContent(title: 'Your week'),
  additionalTooltips: [
    HintTooltip(
      position: TooltipPosition.left,
      content: HintStepContent(title: 'Volume', description: '12.4 t'),
    ),
  ],
)
```

- set `position` explicitly on an extra: `auto` re-picks by free space and can fight the primary for the same side;
- extras are informational by default (no action row, no buttons) — give one a `tooltipBuilder` if a slot needs its own action;
- the engine guarantees slots do not overlap each other or the spotlighted targets, so you position nothing;
- extras carry the tail too (pointing at the primary hole).

---

## 15. Taps — who owns the gesture

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
  overlayTap: const HintTapBehavior.ignore(), // a stray scrim tap must not advance
  targetTap: HintTapBehavior.custom((ctx, details) {
    analytics.log('tapped_target', details.globalPosition);
    doTheRealAction();
    ctx.actions.next();     // move on when it makes sense
  }),
)
```

When to deviate:

- **critical steps** (irreversible actions, permission prompts): `overlayTap: ignore()` plus an explicit `targetTap` custom/button — a tap anywhere must not glide past them;
- **the user must actually use the control** (log the first set): do it from `targetTap: HintTapBehavior.custom(...)` — the widget itself will not receive the tap;
- **drags stay free**: the tap layer is translucent, so scrolling and scroll-through are unaffected (§8).

---

## 16. Motion — animate it yourself

There are no built-in entry animations: the tooltip appears — right for most
product hints. When a step wants motion, it lives in your `tooltipBuilder`
(§11): wrap the card in a `TweenAnimationBuilder` (fade, rise, scale —
anything), and the engine still places it.

The duty: reduce-motion is your check — `MediaQuery.disableAnimations` is
the standard switch, return the plain card when it is set:

```dart
final reduceMotion = MediaQuery.of(context).disableAnimations;
final duration = reduceMotion
    ? Duration.zero
    : const Duration(milliseconds: 400);
if (duration == Duration.zero) return card; // reduce motion: no animation
```

Two habits: keep hint transitions short (a few hundred ms — a hint is not a page
transition), and prefer no animation over a wrong one — a playful bounce on a
destructive step reads as playful at exactly the wrong moment.

---

## 17. Navigation — the tour and the back button

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

## 18. Server-driven tours — what JSON can and cannot carry

`HintTour.fromJson`/`toJson` (your own client, no HTTP dependency in the
package) let a server reword, reorder and restyle a tour you already shipped:

```dart
HintTour tour;
try {
  final body = await http.get(
    Uri.parse('https://cdn.example.com/tours/onboarding'),
  );
  tour = HintTour.fromJson(jsonDecode(body.body) as Map<String, dynamic>);
} catch (_) {
  tour = AppTours.onboarding(); // bundled fallback — never strand the user
}
await controller.start(tour);
```

What the wire format carries: `id`, steps with
`targetId`/`additionalTargets`, titles
and descriptions, `position`, `additionalTooltips`, `stepTimeoutMs`,
`showSkip`, the missing-target policy, historical `tapOn*` bools,
shapes/padding, `autoScroll` and `minShowVersion`.

What it **cannot** carry: builders and callbacks. `titleBuilder`,
`descriptionBuilder`, `tooltipBuilder`, `HintTapBehavior.custom` and the
lifecycle hooks are code-side only. So a server rewrites the copy and the order
of **known** targets — it cannot introduce targets that do not exist in the
binary the user is running.

Practical rules:

- keep the tour id stable — it is the `HintStore` key and the diagnostics id;
- treat the payload as untrusted: an unknown enum value (`position: "middle"`)
  falls back to the field's default and is reported (a debug print plus the
  `onWarning` callback on `HintTour.fromJson` / `HintStep.fromJson` /
  `HintTooltip.fromJson`), and an unknown `targetId`
  is a typo assert in debug / a skipped step in release;
- always keep a bundled fallback — never strand the user on a failed fetch.

For tests and previews, build the tour in Dart (or `HintTour.fromJson(fixture)`).

---

## 19. Testing — headless first

The controller does not need a UI: `HintController.test()` — a
`@visibleForTesting` factory — runs the whole
machine without an overlay (headless by default) — waiting, timeouts, typo
validation, policies,
diagnostics — so a tour flow is a plain unit test:

```dart
final controller = HintController.test(
  registry: HintTargetRegistry(), // your own, never the app singleton
  diagnostics: (e) => events.add(e), // or recorder.call / recorder.add
  // headless: true, // the default — machine only
);

await controller.start(tour);                       // typo → assertion in debug
expect(await controller.tryStart(tour), isFalse);   // busy: atomic guard
controller.next();
expect(controller.currentState, isA<HintWaiting>());
controller.dispose();
```

Notes:

- pass your own `HintTargetRegistry` so a test never depends on the app's targets (or pollutes them) — and pass that **same instance** to every `HintTarget`/`withHint` in the scene (mismatch = every step diagnoses as `timeout`/`unknownTarget`); the package's `test/helpers/tour_harness.dart` shows the pairing;
- assert on diagnostics with your own recording callback (`diagnostics: (e) => …`
  or a tear-off `recorder.call`), not by capturing `debugPrint` output —
  debug builds print the line *and* invoke your callback;
- a typo'd `targetId` is designed for `expectLater(controller.start(tour), throwsAssertionError)` — `start` returns a `Future` so the failure surfaces in the test instead of inside someone's build;
- keep test tours on a short/`Duration.zero` `stepTimeout`, and remember timers must be pumped or a missing target fails after the real 3 s;
- `dispose()` every controller (it is idempotent) — otherwise the registry listener and the timer outlive the test.

For full-fidelity tests (scrim, tooltip copy, taps, positioning) build a real
scene — `MaterialApp` + `HintTarget`s + `HintController()` — the way the
package's own `test/helpers/tour_harness.dart` does, and remember the two-frame
rule: `start` renders the scrim on frame 1 and the tooltip on frame 2, so pump
twice before asserting the tooltip.

---

## 20. The offer dialog — "Want a tour?"

`showHintTourOffer` is the ask-first wrapper: a pre-dialog with an "Apply to all
pages" checkbox that starts the tour on accept.

```dart
final result = await showHintTourOffer(
  context: context,
  controller: controller, // reads the store configured via Hintful.configure
  tour: AppTours.settings(), // HintTour(..., minShowVersion: appVersion)
  pageId: 'settings',     // the page this offer belongs to
  // mark: HintMarkPolicy.manual, // opt-out: record the shown-state yourself (§6)
  labels: HintTourOfferLabels(title: l10n.offerTitle),
);
```

What it handles for you: no dialog when the tour already ran for
`tour.minShowVersion` (returns `alreadyShown`), a decline remembered per
page (and globally when the checkbox is on) under namespaced keys, and a
barrier dismissal counted as a decline — "not now" must not nag. Accepting
runs `startOnce` for you: the shown-state is recorded per `mark:`
(`HintMarkPolicy.onAnyExit` by default — finish/skip/timeout all count — §6
semantics). Pass `HintMarkPolicy.onFinish` or `manual` only when
your policy differs (§6).

Two rules: one offer per page entry point (offer from three buttons and the
dialog appears where the user least expects it), and keep the tour reachable
after a decline (settings, help menu) — the namespaced decline keys in §6 are
what make that possible. `HintTourOfferLabels` carries the copy
(title, body, accept, later, checkbox) — its default comes from
`HintTheme.tourOfferLabels` (localize once in the design system), and a
per-call `labels:` overrides it. `HintTourOfferResult` tells you which
branch was taken if you want to log it.

