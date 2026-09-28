# Migration to hintful

## From `showcaseview`

| showcaseview | hintful |
|---|---|
| `ShowCaseWidget` wrapper + `GlobalKey` per target | `HintTarget(id: 'myId')` — no `GlobalKey`, registry by `id` |
| `ShowcaseView.startShowCase([key1,key2])` | `HintTour(id: 'tour', steps: [HintStep(targetId: 'myId', content: HintStepContent(title: '...'))])` + `controller.start(tour)` |
| `Showcase` with `desc`/`title` | `HintStep(targetId: 'myId', content: HintStepContent(title: '...', description: '...'))` or `tooltipBuilder` for custom |
| Manual `next` via `ShowCaseWidget.of(context).next()` | `controller.next()` / `HintActions.next()` in custom tooltip |

Steps:
1. Replace `ShowCaseWidget` at root with `HintTarget` on each target (`id` must match `targetId`).
2. Build `HintTour` from your step list (a plain `steps:` list; keep your own enum + private helper if you want ids and steps checked together).
3. Create `HintController()` once (renders out of the box), `start(tour)`.

## From `tutorial_coach_mark`

| tutorial_coach_mark | hintful |
|---|---|
| `TutorialCoachMark` + `TargetFocus(identify, keyTarget)` | `HintTarget(id:)` + `HintStep(targetId:)` |
| `createTutorial().show(context)` | `controller.start(tour)` |
| `TargetContent` builder | `HintStep(tooltipBuilder: ...)` or zero-config `HintStepContent` |

Steps:
1. `TargetFocus` → `HintTarget` (`identify` → `id`).
2. `TutorialCoachMark(targets: [...])` → `HintTour(steps: [...])`.
3. `skip`/`next` → `controller.skip()`/`next()` or `HintActions` in tooltip.

## Common

* Server-driven: `HintTour.fromJson(json)` / `toJson()` — steps are flat
  `title`/`description` only; custom `tooltipBuilder` stays code-side.
  Dart param ↔ JSON key: `stepTimeout` ↔ `waitTimeoutMs`,
  tap-bools `tapOnTarget`/`tapOnOverlay`
  ↔ `HintTapBehavior.advance()`/`ignore()` (`true` ⇔ advance).
* Wait-for-target: no manual `Future.delayed` — `stepTimeout` (default 3s)
  + `HintSkipReason.timeout` diagnosis (missing target never renders).
* Zero-idle: remove wrapper when idle — `S1` `idle_zero` stays `0`.

See `example/` for a complete tour (scroll, deferred target, light/dark).
