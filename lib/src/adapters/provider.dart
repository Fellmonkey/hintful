// provider adapter — thin wrapper, core stays `dart:ui+widgets` only.
// Add `provider` to your app.
// Example:
// ```dart
// ChangeNotifierProvider<HintController>(
//   create: (_) => HintController(overlayHostBuilder: defaultOverlayHost()),
//   dispose: (_, c) => c.dispose(),
//   child: ValueListenableBuilder(
//     valueListenable: context.read<HintController>().state, ...
//   ),
// )
// // Or expose state directly: ProxyProvider<HintController, ValueListenable<HintState>>
// ```
library;
