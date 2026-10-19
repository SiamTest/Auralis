# Windows native shutdown fix

The first [GitHub Actions run](https://github.com/SiamTest/Auralis/actions/runs/39206678100), commit `634f23b802888603c18e18bb2679de8e0eb2c957`, built TDLib and the Flutter Windows application. DPAPI, TDLib initialization, local decoding/seeking, and simulated-cache loopback playback checks passed. The process then failed with access violation `0xC0000005` in `libmpv-2.dll`, five seconds after printing its report. Packaging and installer generation did not run.

media_kit 1.2.6 returns from `dispose()` before native shutdown, closing the Dart wakeup callback and scheduling `mpv_terminate_destroy` five seconds later. The matching crash time points to that teardown path. An [upstream callback-lifetime report](https://github.com/media-kit/media-kit/issues/1443) describes a related ordering problem on Android; it does not establish the precise Windows instruction that failed here. The original smoke test exited successfully locally, so the CI crash was not reproduced on this machine.

## Changes

- Vendor media_kit's MIT Dart runtime as `third_party/media_kit`, retaining upstream notices. The app's path dependency applies the same fix in both the Flutter runner and standalone tests; no pub-cache edits are required.
- On Windows, unregister wakeups, stop event polling, drain queued Dart event handlers, terminate/join libmpv in a worker isolate, then close its Dart callback. `Player.dispose()` waits for this sequence. Other platforms retain upstream teardown behavior.
- Print the native smoke report after cleanup. Exercise four create/play/seek/dispose lifecycles in each process.
- CI runs `tool/native_smoke_repeat.dart`, which requires three separate smoke processes to exit successfully. It checks real exit codes, including crashes after printed output; it neither forces process exit nor ignores a failed native test.

## Local verification

Three native smoke processes exited naturally with code 0, covering 12 player lifecycles. Each process passed DPAPI, TDLib 1.8.68 initialization/close, generated WAV playback and seeking, and loopback playback/seeking through the simulated TDLib cache. Each reported `nativeShutdown: {completed: true, cycles: 4}`. Tests used the native binaries and null audio output described in `VERIFICATION.md` and `THIRD_PARTY_NOTICES.md`.

The fixed revision still needs to pass the GitHub runner with its source-built TDLib and compiled Flutter application. This is a teardown fix, not a refresh or licensing audit of the older native libmpv binary. Live Telegram login, audible hardware output, installer creation/installation, and an end-to-end app update remain unverified.

## Apply to the existing repository

Keep the existing Windows runner/header fixes. Replace the following paths with this delivery and commit them together:

- `pubspec.yaml` and `pubspec.lock`
- `third_party/media_kit/` (entire supplied directory, including its LICENSE)
- `tool/native_smoke.dart` and `tool/native_smoke_repeat.dart`
- `.github/workflows/windows.yml` and `analysis_options.yaml`
- Updated README, notices and verification documents

Push that new commit to the repository's branch to start a fresh workflow. Clicking **Re-run jobs** on the old failed run builds its old source and cannot pick up the fix. The current connection has READ permission, so this task has not pushed it remotely.
