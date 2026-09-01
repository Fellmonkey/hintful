import 'package:flutter/widgets.dart';

/// Resolve a transition duration honoring the system reduce-motion setting.
///
/// **The engine's reduce-motion contract**: every hint/tour animation must go
/// through this instead of a hardcoded duration. With
/// `MediaQueryData.disableAnimations` (the OS "reduce motion" accessibility
/// setting, propagated through `MediaQueryData.fromView`) the transition is
/// instant.
///
/// There are no transition animations yet — the tooltip/scrim appear and
/// move without animation. This function is the pinned contract for the ones
/// that follow (covered by tests in `test/engine/motion_test.dart`).
///
/// ```dart
/// final duration = hintTransitionDuration(MediaQuery.of(context), const Duration(milliseconds: 150));
/// ```
Duration hintTransitionDuration(
        MediaQueryData mediaQuery, Duration preferred) =>
    mediaQuery.disableAnimations ? Duration.zero : preferred;
