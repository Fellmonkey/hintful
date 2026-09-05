// bloc adapter — thin Cubit over HintController, ~15 lines.
// Core stays `dart:ui+widgets` only; `bloc` lives in separate `hintful_bloc/` package.
// See `hintful_bloc/` for the publishable package (like `talker_bloc_logger`).
// Example (from that package):
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
