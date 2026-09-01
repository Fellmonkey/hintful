import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/diagnostics.dart';

void main() {
  group('editDistance', () {
    test('exact match — 0', () {
      expect(
        editDistance('statsPeriodSelector', 'statsPeriodSelector'),
        0,
      );
    });

    test('substitution — 1', () {
      expect(editDistance('abc', 'abd'), 1);
    });

    test('insertion — 1', () {
      expect(editDistance('abc', 'abdc'), 1);
    });

    test('deletion — 1', () {
      expect(editDistance('abcd', 'abc'), 1);
    });

    test('completely different — the length', () {
      expect(editDistance('abc', 'xyz'), 3);
    });

    test('empty strings', () {
      expect(editDistance('', ''), 0);
      expect(editDistance('', 'ab'), 2);
      expect(editDistance('ab', ''), 2);
    });
  });

  group('closest-id search', () {
    const known = {'statsPeriodSelector', 'exerciseSelector', 'addSet'};

    test('exact match — distance 0', () {
      expect(findClosestTargetId('addSet', known), 'addSet');
    });

    test('typo within 2 — a candidate is found', () {
      expect(findClosestTargetId('addSetX', known), 'addSet');
      expect(findClosestTargetId('statsPeriodSelectr', known),
          'statsPeriodSelector'); // final 'o' lost → distance 1
    });

    test('nothing similar — null', () {
      expect(findClosestTargetId('totallyUnknown', known), isNull);
    });

    test('top-N sorted by distance, then alphabetically', () {
      const near = {'aaa1', 'aaa2', 'bbb'};
      // 'aaaX': distance 1 to both aaa1 and aaa2; the alphabet decides.
      expect(closestTargetIds('aaaX', near), ['aaa1', 'aaa2']);
      expect(closestTargetIds('aaaX', near, limit: 1), ['aaa1']);
      // 'bbb' is beyond the threshold → does not make it.
      expect(closestTargetIds('aaaX', near), isNot(contains('bbb')));
    });
  });

  group('formatHintSkipped', () {
    test('a single line, reason as a kebab-case name', () {
      final message = formatHintSkipped(
        'statsIntro',
        1,
        'statsPeriodSelector',
        HintSkipReason.targetNotRendered,
        'target not mounted',
      );
      expect(
        message,
        '[hintful] statsIntro step 2 not shown: target-not-rendered'
        " (target 'statsPeriodSelector') — target not mounted",
      );
    });
  });

  group('DebugPrintDiagnostics', () {
    test('prints the formatted line through debugPrint', () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint =
          (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      try {
        const DebugPrintDiagnostics().onHintSkipped(
          't',
          0,
          'x',
          HintSkipReason.timeout,
          'did not appear',
        );
      } finally {
        debugPrint = original;
      }
      expect(logs, hasLength(1));
      expect(logs.single, startsWith('[hintful]'));
      expect(logs.single, contains('timeout'));
      expect(logs.single, contains('did not appear'));
    });
  });
}
