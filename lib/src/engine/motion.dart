import 'package:flutter/widgets.dart';

/// Resolve a transition duration honoring the system reduce-motion setting.
///
/// **The engine's reduce-motion contract**: every hint/tour animation must go
/// through this instead of a hardcoded duration. With
/// `MediaQueryData.disableAnimations` (the OS "reduce motion" accessibility
/// setting, propagated through `MediaQueryData.fromView`) the transition is
/// instant. Currently wired into the sprung tooltip entry
/// (`overlay_engine.dart`); the pulse ring is ambient (opt-in theme flag)
/// and stays as authored.
///
/// ```dart
/// final duration = hintTransitionDuration(MediaQuery.of(context), const Duration(milliseconds: 150));
/// ```
Duration hintTransitionDuration(
        MediaQueryData mediaQuery, Duration preferred) =>
    mediaQuery.disableAnimations ? Duration.zero : preferred;
