// riverpod adapter — thin wrapper, ~15 lines, core stays `dart:ui+widgets` only.
// Add `flutter_riverpod` to your app, not to `hintful` itself.
// Example:
// ```dart
// final hintControllerProvider = Provider<HintController>((ref) {
//   final c = HintController(overlayHostBuilder: defaultOverlayHost());
//   ref.onDispose(c.dispose);
//   return c;
// });
// final hintStateProvider = Provider<ValueListenable<HintState>>((ref) =>
//     ref.watch(hintControllerProvider).state);
// // UI: ValueListenableBuilder(valueListenable: ref.watch(hintStateProvider), ...)
// ```
library;
