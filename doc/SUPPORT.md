# Support policy

hintful has **two maintained lines**. They have identical tour behaviour and
the same frozen public contract; they differ only in which Material library
they compile against and how far back they support Flutter.

| Line | Dependency | SDK floor | Material source | Role |
|---|---|---|---|---|
| **1.x** | `hintful: ^1.0.1` | Dart 3.2 / Flutter 3.16 | bundled `package:flutter/material.dart` (deprecated in Flutter 3.50, diagnostic suppressed in the analyzer config) | **maintenance** for apps that cannot raise their floor |
| **2.x** | `hintful: ^2.0.0` | Dart 3.13 / Flutter 3.47 | `material_ui: ^1.11.1` | **current** development |

## What "maintained" means for 1.x

- Bug fixes and Flutter-compatibility patches continue to be published as
  **1.0.x** from the `1.x` branch.
- The public API is frozen: no new enum values, no signature changes, no new
  features. Compatibility fixes may touch the analyzer config or internals.
- It is checked in CI against Flutter **3.47.0** and **3.50.0**.
- Flutter's deprecation of the bundled Material library is suppressed there
  with a scoped `deprecated_member_use: ignore` and a removal TODO. Flutter
  does not remove deprecated APIs on a fixed schedule; when it does, the 1.x
  line will receive a compatibility patch or reach end of life with notice.

## 2.x

- New features and design-system work land here.
- Both lines run the same test suite; the size golden stays pinned to
  Flutter 3.47.0 and is re-recorded via the `bench-record` workflow when the
  SDK pin moves.

## Companion package

`hintful_prefs` mirrors this split: `hintful_prefs` 1.x depends on `hintful`
1.x, `hintful_prefs` 2.x depends on `hintful` 2.x. Upgrade them together.
