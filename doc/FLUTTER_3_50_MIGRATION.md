# 1.x → 2.x: Flutter 3.50 and `material_ui`

Flutter 3.50 formally deprecates the Material and Cupertino libraries bundled
in the SDK (`package:flutter/material.dart`, `package:flutter/cupertino.dart`)
in favour of the standalone `package:material_ui` / `package:cupertino_ui`
packages. The API is officially available since Flutter 3.47; 2.x adopts it.

## Which line should I use?

| Line | SDK floor | Material source | State |
|---|---|---|---|
| **1.x** | Dart 3.2 / Flutter 3.16 | bundled `flutter/material.dart` (deprecated in 3.50, suppressed in analyzer config) | frozen, maintenance only |
| **2.x** | Dart 3.13 / Flutter 3.47 | `material_ui: ^1.11.1` | current |

If you cannot raise your Flutter floor, stay on `hintful: ^1.0.0`. There is no
behaviour difference between the lines — only the Material library they
compile against.

## What breaks on upgrade

`hintful` exposes Material types in its public API:

```dart
extension HintThemeX on ThemeData { HintTheme get hintTheme; }
factory HintTheme.minimal(ColorScheme scheme);
```

In 2.x those types come from `package:material_ui/material_ui.dart`. If your
app still imports `package:flutter/material.dart`, its `ThemeData` and
`ColorScheme` are **different types** and:

- `Theme.of(context).hintTheme` will not resolve (the extension is on the
  other `ThemeData`);
- `HintTheme.minimal(Theme.of(context).colorScheme)` will not compile.

`MaterialUiCompatibilityBridge` helps with widget subtrees, but the migration
guide explicitly notes it cannot fix API-signature coupling like this — that
part has to be a real import migration.

## Upgrade steps

1. Raise your floors to Dart >= 3.13 / Flutter >= 3.47.
2. `flutter pub add material_ui` (or let the fix tool add it), then:

   ```sh
   dart fix --apply --code=migrate_design_widgets
   ```

3. Replace your own `package:flutter/material.dart` imports with
   `package:material_ui/material_ui.dart`. Check `flutter_localizations`
   delegates too — `GlobalMaterialLocalizations.delegates` now comes from
   `material_ui`.
4. Change the dependency to `hintful: ^2.0.0` and upgrade `hintful_prefs` to
   `^2.0.0` (it republishes the new version ordering helper).
5. Re-run `flutter analyze` and your widget tests. If a third-party widget
   library still imports the SDK Material, wrap that subtree in
   `MaterialUiCompatibilityBridge` and check its public signatures.

## Notes for contributors

- Both lines are tested against Flutter 3.47.0 and 3.50.0 in CI.
- The S7 size golden is recorded on 3.47.0 and is SDK-pinned. Re-record it
  with the `bench-record` workflow before moving the `bundle` job to another
  SDK (or before accepting changed bundle numbers from `material_ui`).
- `benchmark/compare/` deliberately keeps the legacy imports: its rivals
  (`showcaseview`, `tutorial_coach_mark`) still expose SDK Material types.
