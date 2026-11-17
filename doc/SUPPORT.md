# Support policy — 1.x maintenance line

This branch is the **1.x line**: `hintful: ^1.0.1`, Dart 3.2 / Flutter 3.16
and up. It is **alive and maintained**, not abandoned.

- **What continues:** bug fixes and Flutter-compatibility patches, published
  as 1.0.x from this branch. CI checks Flutter **3.47.0** and **3.50.0**.
- **What does not change:** the public API is frozen — no new enum values,
  signatures or features. Compatibility work may touch internals or the
  analyzer config.
- **Material source:** the bundled `package:flutter/material.dart` is kept on
  purpose. Flutter 3.50 deprecates it in favour of `package:material_ui`;
  the diagnostic is suppressed in `analysis_options.yaml` with a removal
  TODO. Flutter does not remove deprecated APIs on a fixed schedule; if it
  does, this line gets a compatibility patch or an announced end of life.
- **Companion:** `hintful_prefs` 1.x depends on `hintful: ^1.0.0` and is
  maintained alongside this line.

The forward line is 2.x (`material_ui`, Dart 3.13 / Flutter 3.47). Upgrading
is optional and documented in the 2.x branch's `doc/FLUTTER_3_50_MIGRATION.md`.
Both lines have identical tour behaviour.
