import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/motion.dart';

void main() {
  group('hintTransitionDuration (reduce-motion contract)', () {
    const preferred = Duration(milliseconds: 150);

    test('honors the preferred duration by default', () {
      expect(
          hintTransitionDuration(const MediaQueryData(), preferred), preferred);
    });

    test('instant when the system reduce-motion setting is on', () {
      expect(
        hintTransitionDuration(
          const MediaQueryData(disableAnimations: true),
          preferred,
        ),
        Duration.zero,
      );
    });

    test('instant even for a zero preferred duration', () {
      expect(
        hintTransitionDuration(
          const MediaQueryData(disableAnimations: true),
          Duration.zero,
        ),
        Duration.zero,
      );
    });
  });
}
