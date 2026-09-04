// GENERATED from flutter_bench_contract (scenario bridge) — do not edit by
// hand. Regenerate: dart run flutter_bench_contract:contract init --force
//
// Dumb bridge: the active_heap smart body lives in the package (lib/scenarios.dart);
// this file only wires the consumer's driver into its own test process.
import 'package:flutter_bench_contract/scenarios.dart';

import '../../drivers/scv_driver.dart';

void main() {
  runContractScenario(
    'active_heap',
    driver: ScvDriver(),
    idleClasses: ['ShowcaseWidget', 'TutorialCoachMark'],
  );
}
