import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/src/engine/store.dart';

void main() {
  group('InMemoryHintStore', () {
    test('never shown → shouldShow true', () {
      final store = InMemoryHintStore();
      expect(store.shouldShow('intro'), isTrue);
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue);
    });

    test('shown → false without minVersion (show once ever)', () {
      final store = InMemoryHintStore()..markShown('intro', '1.0.0');
      expect(store.shouldShow('intro'), isFalse);
    });

    test('shown in an older version → true after a version bump', () {
      final store = InMemoryHintStore()..markShown('intro', '1.0.0');
      expect(store.shouldShow('intro', minVersion: '1.1.0'), isTrue);
    });

    test('shown in the same or newer version → false (no repeat)', () {
      final store = InMemoryHintStore()..markShown('intro', '1.1.0');
      expect(store.shouldShow('intro', minVersion: '1.1.0'), isFalse);
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isFalse);
    });

    test('keys are independent', () {
      final store = InMemoryHintStore();
      store.markShown('intro', '1.0.0');
      store.markShown('other', '2.0.0');
      expect(store.shouldShow('intro', minVersion: '1.1.0'), isTrue);
      expect(store.shouldShow('other', minVersion: '2.0.0'), isFalse);
      expect(store.shouldShow('other', minVersion: '2.1.0'), isTrue);
    });

    test('markShown overwrites the last shown version', () {
      final store = InMemoryHintStore()
        ..markShown('intro', '1.0.0')
        ..markShown('intro', '1.5.0');
      expect(store.shouldShow('intro', minVersion: '1.4.0'), isFalse);
      expect(store.shouldShow('intro', minVersion: '1.6.0'), isTrue);
    });

    test('clear — everything shows again', () {
      final store = InMemoryHintStore()..markShown('intro', '1.1.0');
      store.clear();
      expect(store.shouldShow('intro', minVersion: '1.1.0'), isTrue);
      expect(store.shouldShow('intro'), isTrue);
    });
  });

  group('CallbackHintStore', () {
    test('same version semantics as InMemoryHintStore over read/write', () {
      final backing = <String, String>{};
      final store = CallbackHintStore(
        read: (key) => backing[key],
        write: (key, version) => backing[key] = version,
      );

      expect(store.shouldShow('intro', minVersion: '1.0.0'), isTrue);
      store.markShown('intro', '1.0.0');
      expect(store.shouldShow('intro'), isFalse);
      expect(store.shouldShow('intro', minVersion: '1.1.0'), isTrue);
      expect(store.shouldShow('intro', minVersion: '1.0.0'), isFalse);
      expect(backing['intro'], '1.0.0');
    });

    test('keys are independent', () {
      final backing = <String, String>{};
      final store = CallbackHintStore(
        read: (key) => backing[key],
        write: (key, version) => backing[key] = version,
      );
      store.markShown('intro', '1.0.0');
      store.markShown('other', '2.0.0');
      expect(store.shouldShow('intro', minVersion: '1.1.0'), isTrue);
      expect(store.shouldShow('other', minVersion: '2.0.0'), isFalse);
    });

    test('multi-digit version segments compare numerically', () {
      final backing = <String, String>{'intro': '2.9.0'};
      final store = CallbackHintStore(
        read: (key) => backing[key],
        write: (key, version) => backing[key] = version,
      );
      expect(store.shouldShow('intro', minVersion: '2.10.0'), isTrue);
      expect(store.shouldShow('intro', minVersion: '2.9.0'), isFalse);
    });
  });

  group('HintStore.shouldShowVersion', () {
    test('never shown → true, minVersion or not', () {
      expect(
        HintStore.shouldShowVersion(lastShown: null, minVersion: null),
        isTrue,
      );
      expect(
        HintStore.shouldShowVersion(lastShown: null, minVersion: '1.0.0'),
        isTrue,
      );
    });

    test('shown without minVersion → false (show once ever)', () {
      expect(
        HintStore.shouldShowVersion(lastShown: '1.0.0', minVersion: null),
        isFalse,
      );
    });

    test('shown older → true; same or newer → false', () {
      expect(
        HintStore.shouldShowVersion(lastShown: '1.9.0', minVersion: '1.10.0'),
        isTrue,
      );
      expect(
        HintStore.shouldShowVersion(lastShown: '1.10.0', minVersion: '1.10.0'),
        isFalse,
      );
      expect(
        HintStore.shouldShowVersion(lastShown: '2.0.0', minVersion: '1.9.0'),
        isFalse,
      );
    });

    test('both shipped stores answer through it', () {
      final backing = <String, String>{'intro': '1.0.0'};
      final cb = CallbackHintStore(
        read: (key) => backing[key],
        write: (key, version) => backing[key] = version,
      );
      final mem = InMemoryHintStore()..markShown('intro', '1.0.0');

      for (final min in [null, '0.9.0', '1.0.0', '1.1.0', '2.3']) {
        final expected = HintStore.shouldShowVersion(
          lastShown: '1.0.0',
          minVersion: min,
        );
        expect(cb.shouldShow('intro', minVersion: min), expected,
            reason: 'CallbackHintStore, min=$min');
        expect(mem.shouldShow('intro', minVersion: min), expected,
            reason: 'InMemoryHintStore, min=$min');
      }
    });
  });

  group('compareVersions', () {
    test('segment-wise and numeric: 1.10.0 > 1.9.0', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0));
    });

    test('a missing segment counts as 0: 2.3 == 2.3.0', () {
      expect(compareVersions('2.3', '2.3.0'), 0);
      expect(compareVersions('2.3.1', '2.3'), greaterThan(0));
    });

    test('non-numeric segments compare lexically', () {
      expect(compareVersions('1.0.0-dev', '1.0.0-alpha'), greaterThan(0));
    });
  });
}
