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
    );
  }
}

/// Access to the hint theme from [ThemeData]: `Theme.of(context).hintTheme`.
extension HintThemeX on ThemeData {
  HintTheme get hintTheme =>
      extensions[HintTheme] as HintTheme? ?? HintTheme.minimal(colorScheme);
}
