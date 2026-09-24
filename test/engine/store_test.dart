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
}
