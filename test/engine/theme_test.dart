import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/theme/hint_theme.dart';

void main() {
  group('HintTheme.minimal', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

    test('the ColorScheme inverseSurface pair, not a hardcode', () {
      final theme = HintTheme.minimal(scheme);
      expect(theme.tooltipBackground, scheme.inverseSurface);
      expect(theme.tooltipForeground, scheme.onInverseSurface);
    });

    test('title/description styles are set (zero-config default)', () {
      final theme = HintTheme.minimal(scheme);
      expect(theme.tooltipTitleStyle, isNotNull);
      expect(theme.tooltipDescriptionStyle, isNotNull);
      expect(theme.tooltipTitleStyle?.color, scheme.onInverseSurface);
    });

    test('showTail defaults to true (the arrow is on by default)', () {
      final theme = HintTheme.minimal(scheme);
      expect(theme.showTail, isTrue);
    });
  });

  group('HintThemeX.hintTheme', () {
    test('without registration — minimal default from colorScheme', () {
      final data =
          ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal));
      expect(data.hintTheme, isA<HintTheme>());
      expect(
        data.hintTheme.tooltipBackground,
        data.colorScheme.inverseSurface,
      );
    });

    test('with registration — custom theme', () {
      const custom = HintTheme(
        tooltipBackground: Color(0xFF123456),
        tooltipForeground: Color(0xFFFFFFFF),
        scrimColor: Color(0x80000000),
        tooltipRadius: BorderRadius.all(Radius.circular(2)),
        tooltipPadding: EdgeInsets.all(4),
      );
      final data = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        extensions: [custom],
      );
      expect(data.hintTheme, same(custom));
    });
  });

  group('copyWith / lerp', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final a = HintTheme.minimal(scheme);
    final b = HintTheme.minimal(
      ColorScheme.fromSeed(seedColor: Colors.deepOrange),
    );

    test('copyWith without arguments — the same object by values', () {
      expect(a.copyWith().tooltipBackground, a.tooltipBackground);
      expect(a.copyWith().tooltipTitleStyle, a.tooltipTitleStyle);
    });

    test('copyWith changes exactly the given field', () {
      final changed = a.copyWith(tooltipPadding: const EdgeInsets.all(2));
      expect(changed.tooltipPadding, const EdgeInsets.all(2));
      expect(changed.tooltipBackground, a.tooltipBackground);
      expect(changed.showTail, a.showTail);
    });

    test('copyWith(showTail: false) turns the tail off', () {
      expect(a.copyWith(showTail: false).showTail, isFalse);
      expect(a.showTail, isTrue); // the original is unchanged
    });

    test('lerp(0) = a, lerp(1) = b, the middle — interpolation', () {
      expect(a.lerp(b, 0.0).tooltipBackground, a.tooltipBackground);
      expect(a.lerp(b, 1.0).tooltipBackground, b.tooltipBackground);
      final mid = a.lerp(b, 0.5);
      expect(
        mid.tooltipBackground,
        Color.lerp(a.tooltipBackground, b.tooltipBackground, 0.5),
      );
    });

    test('lerp(null) — returns this (animation "theme appeared")', () {
      expect(a.lerp(null, 0.5), same(a));
    });

    test('lerp of showTail picks by the interpolation point', () {
      final off = a.copyWith(showTail: false);
      expect(a.lerp(off, 0.0).showTail, isTrue);
      expect(a.lerp(off, 1.0).showTail, isFalse);
    });
  });
}
