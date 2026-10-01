import 'package:flutter/widgets.dart';

import '../engine/registry.dart';
import '../engine/specs.dart';
import 'hint_target.dart';

/// Ergonomic sugar over [HintTarget]: `child.withHint('id')` instead of
/// `HintTarget(id: 'id', child: child)`. Every constructor parameter
/// (registry, semantics label, focus shape/padding, key) is available here
/// as a named argument too — the two forms differ only in spelling.
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
