# Pull request — hintful

## What changed
<!-- Describe what and why, whether it touches lib/ or benchmark/ -->

## Final performance gate
<!-- ~20 min on Android emulator, maintainer-triggered -->
The full benchmark (S1–S7 on an Android emulator, ~20 min) is not run on every PR.

To request a performance check, please ping @Fellmonkey — I will add the `bench` label to trigger the gate. If it passes, the PR is good to merge. If it reports a regression, the bot will add a comment with details.
