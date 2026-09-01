import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Hint theme — a product design-system `ThemeExtension`.
///
/// The product describes hints as part of its design system: register
/// [HintTheme] in `ThemeData.extensions` — and every tooltip/scrim
/// inherits it automatically, with no per-screen configuration. Light/dark is
/// solved by the same mechanism as the rest of the UI (different `ThemeData`).
///
/// Zero-config: without registration, [HintThemeX.hintTheme] returns the
/// [HintTheme.minimal] default derived from `ColorScheme` — a hint looks
/// "Material-native" rather than "library-ish", even before the product
/// defines its own theme.
@immutable
class HintTheme extends ThemeExtension<HintTheme> {
  const HintTheme({
    required this.tooltipBackground,
    required this.tooltipForeground,
    required this.scrimColor,
    required this.tooltipRadius,
    required this.tooltipPadding,
    this.tooltipTitleStyle,
    this.tooltipDescriptionStyle,
    this.showTail = true,
    this.imageFilter,
    this.showPulse = false,
  });

  /// Tooltip background (default — `inverseSurface` of the ColorScheme).
  final Color tooltipBackground;

  /// Tooltip text and accents (default — `onInverseSurface`).
  final Color tooltipForeground;

  /// Screen dimming around the target (scrim).
  final Color scrimColor;

  final BorderRadius tooltipRadius;
  final EdgeInsets tooltipPadding;

  /// Title/description styles; null — the tooltip resolves defaults from
  /// [tooltipForeground] (a partially custom theme does not break
  /// zero-config).
  final TextStyle? tooltipTitleStyle;
  final TextStyle? tooltipDescriptionStyle;

  /// The tail (arrow from the tooltip toward the target). On by default —
  /// it is what visually ties the tooltip to the hole; set false for a
  /// floating-callout look. Applies to the default tooltip only: a custom
  /// `tooltipBuilder` owns its look entirely.
  final bool showTail;

  /// Optional background blur behind the scrim (`ImageFilter.blur(...)`),
  /// replacing the plain dim with a "frosted" look. Off by default: the
  /// plain dim is cheaper (zero backdrop sampling). When set, the scrim is
  /// rendered in the global layer (the hole rect comes from the position
  /// watcher, one frame behind the compositor — the same lag as the
  /// tooltip), instead of the live follower painter.
  final ImageFilter? imageFilter;

  /// A pulsing ring around the primary target (Material feature-discovery
  /// pattern). Off by default; the animation runs only while a step is
  /// active with this flag on.
  final bool showPulse;

  /// Default derived from a [ColorScheme] (inverseSurface pair).
  factory HintTheme.minimal(ColorScheme scheme) {
    final onSurface = scheme.onInverseSurface;
    return HintTheme(
      tooltipBackground: scheme.inverseSurface,
      tooltipForeground: onSurface,
      scrimColor: const Color(0x80000000), // black 50%
      tooltipRadius: BorderRadius.circular(12),
      tooltipPadding: const EdgeInsets.all(16),
      tooltipTitleStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      tooltipDescriptionStyle: TextStyle(
        fontSize: 13,
        // withAlpha (not deprecated across the supported 3.10+ range;
        // withOpacity was deprecated in 3.27 in favor of withValues — 3.27+).
        color: onSurface.withAlpha(191), // 75% opacity
      ),
    );
  }

  @override
  HintTheme copyWith({
    Color? tooltipBackground,
    Color? tooltipForeground,
    Color? scrimColor,
    BorderRadius? tooltipRadius,
    EdgeInsets? tooltipPadding,
    TextStyle? tooltipTitleStyle,
    TextStyle? tooltipDescriptionStyle,
    bool? showTail,
    ImageFilter? imageFilter,
    bool? showPulse,
  }) {
    return HintTheme(
      tooltipBackground: tooltipBackground ?? this.tooltipBackground,
      tooltipForeground: tooltipForeground ?? this.tooltipForeground,
      scrimColor: scrimColor ?? this.scrimColor,
      tooltipRadius: tooltipRadius ?? this.tooltipRadius,
      tooltipPadding: tooltipPadding ?? this.tooltipPadding,
      tooltipTitleStyle: tooltipTitleStyle ?? this.tooltipTitleStyle,
      tooltipDescriptionStyle:
          tooltipDescriptionStyle ?? this.tooltipDescriptionStyle,
      showTail: showTail ?? this.showTail,
      imageFilter: imageFilter ?? this.imageFilter,
      showPulse: showPulse ?? this.showPulse,
    );
  }

  @override
  HintTheme lerp(HintTheme? other, double t) {
    // Component-wise; when other == null (animation "theme appeared") —
    // return this rather than a "black screen".
    if (other == null) return this;
    return HintTheme(
      tooltipBackground:
          Color.lerp(tooltipBackground, other.tooltipBackground, t)!,
      tooltipForeground:
          Color.lerp(tooltipForeground, other.tooltipForeground, t)!,
      scrimColor: Color.lerp(scrimColor, other.scrimColor, t)!,
      tooltipRadius: BorderRadius.lerp(tooltipRadius, other.tooltipRadius, t)!,
      tooltipPadding: EdgeInsets.lerp(tooltipPadding, other.tooltipPadding, t)!,
      tooltipTitleStyle:
          TextStyle.lerp(tooltipTitleStyle, other.tooltipTitleStyle, t),
      tooltipDescriptionStyle: TextStyle.lerp(
        tooltipDescriptionStyle,
        other.tooltipDescriptionStyle,
        t,
      ),
      showTail: t < 0.5 ? showTail : other.showTail,
      // No lerp for the filter (filters do not interpolate) — pick by point.
      imageFilter: t < 0.5 ? imageFilter : other.imageFilter,
      showPulse: t < 0.5 ? showPulse : other.showPulse,
    );
  }
}

/// Access to the hint theme from [ThemeData]: `Theme.of(context).hintTheme`.
extension HintThemeX on ThemeData {
  HintTheme get hintTheme =>
      extensions[HintTheme] as HintTheme? ?? HintTheme.minimal(colorScheme);
}
