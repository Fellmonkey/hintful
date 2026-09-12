// bloc adapter — a thin Cubit over HintController, ~15 lines.
// Core stays `dart:ui+widgets`: `bloc` never enters hintful's dependencies,
// so the adapter lives in your app (or your own package next to it).
// Example:
// ```dart
// class HintCubit extends Cubit<HintState> {
//   HintCubit(this.controller) : super(controller.state.value) {
//     controller.state.addListener(() => emit(controller.state.value));
//   }
//   final HintController controller;
//   void next() => controller.next();
// }
// ```
library;
