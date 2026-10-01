import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

import '../labels.dart';
import '../specs.dart' show kHintHoleRadius;

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
  /// Creates a theme from the required colors and optional style overrides.
  const HintTheme({
    required this.tooltipBackground,
    required this.tooltipForeground,
    required this.scrimColor,
    required this.tooltipRadius,
    required this.tooltipPadding,
    this.holeRadius = kHintHoleRadius,
    this.tooltipTitleStyle,
    this.tooltipDescriptionStyle,
    this.showTail = true,
    this.imageFilter,
    this.showPulse = false,
    this.tooltipLabels = const HintTooltipLabels(),
    this.tourOfferLabels = const HintTourOfferLabels(),
  });

  /// Tooltip background (default — `inverseSurface` of the ColorScheme).
  final Color tooltipBackground;

  /// Tooltip text and accents (default — `onInverseSurface`).
  final Color tooltipForeground;

  /// Screen dimming around the target (scrim).
  final Color scrimColor;

  /// Tooltip corner radius (default via [HintTheme.minimal] — 12).
  final BorderRadius tooltipRadius;

  /// Inner padding of the tooltip (default via [HintTheme.minimal] — 16).
  final EdgeInsets tooltipPadding;

  /// Corner radius of a `FocusShape.roundedRect` spotlight hole (default 12).
  /// Clamped to half the shortest side of the hole, so a tiny target cannot
  /// invert itself; the other two [FocusShape]s ignore it. The pulse ring
  /// uses the same value — ring and hole stay one shape.
  final double holeRadius;

  /// Title/description styles; null — the tooltip resolves defaults from
  /// [tooltipForeground] (a partially custom theme does not break
  /// zero-config).
  final TextStyle? tooltipTitleStyle;

  /// Description style; null — the tooltip resolves defaults from
  /// [tooltipForeground] (same contract as [tooltipTitleStyle]).
  final TextStyle? tooltipDescriptionStyle;

  /// The tail (arrow from the tooltip toward the target). On by default —
  /// it is what visually ties the tooltip to the hole; set false for a
  /// floating-callout look.
  ///
  /// The engine wraps it around every tooltip slot — the default tooltip, a
  /// custom `tooltipBuilder` and multi-content slots (`additionalTooltips`) — and
  /// it always points at the primary target's hole. A custom tooltip that
  /// draws its own pointer should turn it off.
  final bool showTail;

  /// Optional background blur behind the scrim (`ImageFilter.blur(...)`),
  /// replacing the plain dim with a "frosted" look. Off by default: the
  /// plain dim is cheaper (zero backdrop sampling). Its clip is rebuilt from
  /// the hole snapshot on every movement write (one frame behind the
  /// compositor - the same lag as the tooltip), while the pulse ring reads
  /// the target's transform live at paint time.
  final ImageFilter? imageFilter;

  /// A pulsing ring around the primary target (Material feature-discovery
  /// pattern). Off by default; the animation runs only while a step is
  /// active with this flag on.
  final bool showPulse;

  /// Button + announcement strings of the zero-config tooltip (English by
  /// default): localize once here, every [DefaultTooltip] inherits it.
  final HintTooltipLabels tooltipLabels;

  /// Offer-dialog copy for the "Want a tour?" pre-dialog (English by
  /// default): localize once here — `showHintTourOffer` without an explicit
  /// `labels:` inherits it, the same design-system path as [tooltipLabels].
  final HintTourOfferLabels tourOfferLabels;

  /// Default derived from a [ColorScheme] (inverseSurface pair).
  factory HintTheme.minimal(ColorScheme scheme) {
    final onSurface = scheme.onInverseSurface;
    return HintTheme(
      tooltipBackground: scheme.inverseSurface,
      tooltipForeground: onSurface,
      scrimColor: const Color(0x80000000), // black 50%
      tooltipRadius: BorderRadius.circular(12),
      tooltipPadding: const EdgeInsets.all(16),
      tooltipTitleStyle: hintDefaultTitleStyle(onSurface),
      tooltipDescriptionStyle: hintDefaultDescriptionStyle(onSurface),
    );
  }

  /// Same theme with the given fields replaced. An omitted argument — and an
  /// explicit `null` — keeps the current value, the same rule every field
  /// follows. The three nullable overrides ([tooltipTitleStyle],
  /// [tooltipDescriptionStyle], [imageFilter]) are dropped with
  /// [withoutTitleStyle], [withoutDescriptionStyle] and [withoutImageFilter].
  @override
  HintTheme copyWith({
    Color? tooltipBackground,
    Color? tooltipForeground,
    Color? scrimColor,
    BorderRadius? tooltipRadius,
    EdgeInsets? tooltipPadding,
    double? holeRadius,
    TextStyle? tooltipTitleStyle,
    TextStyle? tooltipDescriptionStyle,
    bool? showTail,
    ImageFilter? imageFilter,
    bool? showPulse,
    HintTooltipLabels? tooltipLabels,
    HintTourOfferLabels? tourOfferLabels,
  }) =>
      _raw(
        tooltipBackground: tooltipBackground ?? this.tooltipBackground,
        tooltipForeground: tooltipForeground ?? this.tooltipForeground,
        scrimColor: scrimColor ?? this.scrimColor,
        tooltipRadius: tooltipRadius ?? this.tooltipRadius,
        tooltipPadding: tooltipPadding ?? this.tooltipPadding,
        holeRadius: holeRadius ?? this.holeRadius,
        tooltipTitleStyle: tooltipTitleStyle ?? _keep,
        tooltipDescriptionStyle: tooltipDescriptionStyle ?? _keep,
        showTail: showTail ?? this.showTail,
        imageFilter: imageFilter ?? _keep,
        showPulse: showPulse ?? this.showPulse,
        tooltipLabels: tooltipLabels ?? this.tooltipLabels,
        tourOfferLabels: tourOfferLabels ?? this.tourOfferLabels,
      );

  /// The same theme without the background blur: the plain dim scrim comes
  /// back. [copyWith] cannot say it (a `null` argument keeps, like everywhere
  /// else), so clearing has its own call.
  HintTheme withoutImageFilter() => _raw(imageFilter: null);

  /// The same theme without a title-style override: the tooltip resolves its
  /// default from [tooltipForeground] again.
  HintTheme withoutTitleStyle() => _raw(tooltipTitleStyle: null);

  /// The same theme without a description-style override — same fallback as
  /// [withoutTitleStyle].
  HintTheme withoutDescriptionStyle() => _raw(tooltipDescriptionStyle: null);

  /// One rebuild with every field spelled out: `_keep` (the default) means
  /// "take it from this theme", an explicit `null` means "drop it". Private —
  /// the public [copyWith] is fully typed; this is only how the `without*`
  /// clearers express "clear to null" without an `Object?` parameter.
  HintTheme _raw({
    Object? tooltipBackground = _keep,
    Object? tooltipForeground = _keep,
    Object? scrimColor = _keep,
    Object? tooltipRadius = _keep,
    Object? tooltipPadding = _keep,
    Object? holeRadius = _keep,
    Object? tooltipTitleStyle = _keep,
    Object? tooltipDescriptionStyle = _keep,
    Object? showTail = _keep,
    Object? imageFilter = _keep,
    Object? showPulse = _keep,
    Object? tooltipLabels = _keep,
    Object? tourOfferLabels = _keep,
  }) =>
      HintTheme(
        tooltipBackground: _or(tooltipBackground, this.tooltipBackground),
        tooltipForeground: _or(tooltipForeground, this.tooltipForeground),
        scrimColor: _or(scrimColor, this.scrimColor),
        tooltipRadius: _or(tooltipRadius, this.tooltipRadius),
        tooltipPadding: _or(tooltipPadding, this.tooltipPadding),
        holeRadius: _or(holeRadius, this.holeRadius),
        tooltipTitleStyle: _or(tooltipTitleStyle, this.tooltipTitleStyle),
        tooltipDescriptionStyle:
            _or(tooltipDescriptionStyle, this.tooltipDescriptionStyle),
        showTail: _or(showTail, this.showTail),
        imageFilter: _or(imageFilter, this.imageFilter),
        showPulse: _or(showPulse, this.showPulse),
        tooltipLabels: _or(tooltipLabels, this.tooltipLabels),
        tourOfferLabels: _or(tourOfferLabels, this.tourOfferLabels),
      );

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
      holeRadius: holeRadius + (other.holeRadius - holeRadius) * t,
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
      // Strings do not interpolate either — same point-pick.
      tooltipLabels: t < 0.5 ? tooltipLabels : other.tooltipLabels,
      tourOfferLabels: t < 0.5 ? tourOfferLabels : other.tourOfferLabels,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HintTheme &&
      other.tooltipBackground == tooltipBackground &&
      other.tooltipForeground == tooltipForeground &&
      other.scrimColor == scrimColor &&
      other.tooltipRadius == tooltipRadius &&
      other.tooltipPadding == tooltipPadding &&
      other.holeRadius == holeRadius &&
      other.tooltipTitleStyle == tooltipTitleStyle &&
      other.tooltipDescriptionStyle == tooltipDescriptionStyle &&
      other.showTail == showTail &&
      other.imageFilter == imageFilter &&
      other.showPulse == showPulse &&
      other.tooltipLabels == tooltipLabels &&
      other.tourOfferLabels == tourOfferLabels;

  @override
  int get hashCode => Object.hash(
        tooltipBackground,
        tooltipForeground,
        scrimColor,
        tooltipRadius,
        tooltipPadding,
        holeRadius,
        tooltipTitleStyle,
        tooltipDescriptionStyle,
        showTail,
        imageFilter,
        showPulse,
        tooltipLabels,
        tourOfferLabels,
      );
}

/// Access to the hint theme from [ThemeData]: `Theme.of(context).hintTheme`.
extension HintThemeX on ThemeData {
  /// This theme's [HintTheme]; unregistered — the zero-config
  /// [HintTheme.minimal] default derived from [colorScheme].
  HintTheme get hintTheme =>
      extensions[HintTheme] as HintTheme? ?? HintTheme.minimal(colorScheme);
}

/// "Keep the current value" marker for [HintTheme._raw] — a private sentinel,
/// never exposed in a public signature (that is the whole point: a typed
/// `copyWith` cannot be called with a wrong-typed argument).
const Object _keep = Object();

/// [_keep] → [current]; anything else → the value, cast to [T]'s type (an
/// explicit `null` clears a nullable field).
T _or<T>(Object? value, T current) =>
    identical(value, _keep) ? current : value as T;

/// Default title style of the zero-config tooltip, derived from the
/// [foreground]. Shared by [HintTheme.minimal] and `DefaultTooltip` so the
/// "no explicit style" path and the zero-config theme cannot drift.
/// @internal — not part of the barrel contract.
@internal
TextStyle hintDefaultTitleStyle(Color foreground) =>
    TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: foreground);

/// Default description style — the foreground at 75 % opacity, the value the
/// WCAG AA contrast tests assert. Shared by [HintTheme.minimal] and
/// `DefaultTooltip` (same contract as [hintDefaultTitleStyle]);
/// `withAlpha` is not deprecated across the supported 3.16+ range (unlike
/// `withOpacity`, deprecated in 3.27 in favor of `withValues`).
/// @internal — not part of the barrel contract.
@internal
TextStyle hintDefaultDescriptionStyle(Color foreground) =>
    TextStyle(fontSize: 13, color: foreground.withAlpha(191)); // 75% opacity
