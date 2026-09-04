// GENERATED from flutter_bench_contract (scenario bridge) — do not edit by
// hand. Regenerate: dart run flutter_bench_contract:contract init --force
//
// Dumb bridge: the idle_resources smart body lives in the package (lib/scenarios.dart);
// this file only wires the consumer's driver into its own test process.
import 'package:flutter_bench_contract/scenarios.dart';

import '../drivers/hintful_driver.dart';

void main() {
  runContractScenario(
    'idle_resources',
    driver: HintfulDriver(),
    idleClasses: ['HintController', 'HintOverlayHost'],
  );
}
