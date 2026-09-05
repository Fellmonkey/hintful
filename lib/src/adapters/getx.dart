// getx adapter — thin wrapper, core stays `dart:ui+widgets` only.
// Add `get` to your app.
// Example:
// ```dart
// class HintGetxController extends GetxController {
//   final HintController hint = HintController(overlayHostBuilder: defaultOverlayHost());
//   HintState get state => hint.state.value;
//   HintGetxController() { hint.state.addListener(update); }
//   @override onClose() { hint.dispose(); super.onClose(); }
//   void next() => hint.next();
// }
// // UI: GetBuilder<HintGetxController>(builder: (c) => Text(c.state.toString()))
// ```
library;
