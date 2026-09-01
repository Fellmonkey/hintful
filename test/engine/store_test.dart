import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/store.dart';

void main() {
  group('compareVersions', () {
    test('numeric segments', () {
      expect(compareVersions('2.3.0', '2.3.1'), lessThan(0));
      expect(compareVersions('2.3.1', '2.3.0'), greaterThan(0));
      expect(compareVersions('2.3.0', '2.3.0'), 0);
    });

    test('multi-digit segments compare numerically (2.10 > 2.9)', () {
      expect(compareVersions('2.10.0', '2.9.0'), greaterThan(0));
    });

    test('missing segments are zero (2.3 == 2.3.0)', () {
      expect(compareVersions('2.3', '2.3.0'), 0);
      expect(compareVersions('2', '2.0.0'), 0);
    });

    test('non-numeric segments compare lexically', () {
      expect(compareVersions('1.0.0+1', '1.0.0+2'), lessThan(0));
      expect(compareVersions('1.0.0', '1.0.0+1'), lessThan(0));
    });
  });

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
}
