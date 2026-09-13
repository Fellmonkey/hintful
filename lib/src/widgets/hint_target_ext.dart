import 'package:flutter/widgets.dart';

import '../engine/registry.dart';
import '../engine/specs.dart';
import 'hint_target.dart';

/// Ergonomic sugar over [HintTarget]: `child.withHint('id')` instead of
/// `HintTarget(id: 'id', child: child)`. Keep `HintTarget` for full
/// control (custom registry, semantics) — this is just the short path.
extension HintTargetX on Widget {
  /// Wrap this widget as a tour target.
  Widget withHint(
    String id, {
    Key? key,
    HintTargetRegistry? registry,
    String? semanticsLabel,
    FocusShape? focusShape,
    double? focusPadding,
  }) =>
      HintTarget(
        key: key,
        id: id,
        registry: registry,
        semanticsLabel: semanticsLabel,
        focusShape: focusShape,
        focusPadding: focusPadding,
        child: this,
      );
}
