# Verification record — Windows x64, 19 October 2026

Environment: Windows 11 24H2 (10.0.26100.9550), Flutter 3.47.1 (framework `6655482ec0`), Dart 3.13.1. Tests were run locally in this task, not on GitHub Actions.

## Automated tests

Original milestone: **12 tests passed**. The release/updater follow-up adds version, integrity, redirect, installer-handoff and packaging coverage; its final results are recorded below.

- Audio-message/document parsing, metadata, and non-audio document exclusion.
- Serialized atomic settings persistence, volume clamping, Windows DPAPI encryption/decryption and tamper rejection.
- Duplicate queue entries, active-entry reorder tracking, next/previous, repeat and clear.
- Concurrent source opens, capability URL expiration, and a new seek superseding a stalled range.
- Full/open-ended/suffix range parsing and invalid/multipart rejection.
- Real localhost HTTP responses: buffered byte delivery, exact body bytes, Content-Range, HEAD, forbidden capability and 416 responses.
- Stalled-buffer error and request termination.
- Phone/code/2FA request construction, encrypted-database parameters, chat updates, document pagination, and invalid credential rejection. These authorization tests use a **fake transport**.
- Flutter navigation, empty states, sign-in entry, queue, now-playing and settings at 1280×800, 760×650 and 520×560 logical pixels, without layout exceptions. Previews use locally installed Segoe UI and Flutter Material icons.

`flutter analyze --no-pub --fatal-infos`: final result recorded as clean after the last source formatting/check pass. PowerShell's parser accepted both build/packaging scripts. Parsing does not demonstrate that native compilation or packaging succeeds.

## Native smoke test

Command: `dart run tool/native_smoke.dart <libmpv-2.dll> <tdjson.dll>`.

Final measured run:

```json
{
  "dpapi": "encrypted credential round-trip passed",
  "tdlib": {
    "version": "1.8.68",
    "initialAuthState": "authorizationStateWaitTdlibParameters"
  },
  "libmpv": {
    "durationSeconds": 12,
    "playedPositionMs": 250,
    "seekPositionMs": 7049,
    "output": "null (muted)"
  },
  "loopbackPlayback": {
    "tdSource": "simulated cache (no account)",
    "requests": 19,
    "seekPositionMs": 4050
  }
}
```

The test used a generated WAV, actual native decoding, actual time progression, pause/resume, seeking, and real HTTP between libmpv and Auralis's proxy. The proxy's TDLib **file-cache responses were simulated**. This verifies the playback/proxy path, not authenticated Telegram networking. Output was routed to a null audio device; audible hardware output was not checked. The local native binaries were checksum-verified; provenance is in `THIRD_PARTY_NOTICES.md`.

Paused libmpv time updates did not immediately advance the smoke-test state until playback resumed. The UI backend now updates the displayed seek position when the seek command succeeds. The successful seek measurements above were taken during resumed playback.

## Build attempt and outstanding work

`flutter build windows --release` failed before compilation with:

```text
Unable to find suitable Visual Studio toolchain. Please run `flutter doctor` for more details.
```

Flutter Doctor confirmed Visual Studio is not installed. The signed Microsoft Build Tools bootstrapper was attempted with a project-local install location. It returned code 1602 / `0x80070642`, with the installer log reporting that elevation may have been declined. No compiler installation was completed. No executable or installer was produced, launched, or tested.

The checked-in GitHub Actions workflow, TDLib MSVC source build, full app packaging, and Inno Setup recipe have not been executed end to end. ZIP/source/checksum packaging and tag matching have separately been tested with fixture files. A live Telegram account login, chat pagination against Telegram, actual channel downloads, real-network buffer recovery/seeking, and fresh-machine installation remain required. Complete the native license/source and security audit before public binary release. Do not treat this record as evidence those outstanding checks passed.

## Release and updater follow-up

Final local check: `flutter analyze --no-pub --fatal-infos` found no issues, and `flutter test --no-pub --reporter expanded` passed **all 22 tests**. This includes the real helper test and fixture packaging test described below. All three PowerShell scripts parsed successfully; the updated workflow structure was parsed separately.

Configured public update repository: `SiamTest/Auralis`. The GitHub connection reports READ permission and the repository was empty when inspected. No source push, Actions run, or release publication was performed.

New automated checks cover:

- Numeric stable-version ordering; rejecting prerelease/malformed tags, older releases, drafts, incorrect asset names/URLs, missing digests and invalid sizes.
- Download byte counts, digest validation, tampered/truncated files, safe GitHub CDN redirects and blocking other hosts, rate limits, missing releases, and preference persistence.
- Rehash before install, helper-before-exit ordering, and cancelling the helper if application exit is cancelled.
- A **real hidden Windows PowerShell helper** invoked with a harmless `.cmd` installer stand-in: it waited for a separate process to exit, verified the file, passed arguments/paths containing spaces, and rejected an incorrect hash. It installed no software. This test found and fixed reliance on PowerShell module discovery; helper hashing now uses .NET directly.
- Real PowerShell ZIP/source/checksum packaging with temporary marker files and a temporary Git repository, validating pubspec-based names and rejecting a mismatched tag. The fixture's EXE/DLL marker files were never executed and are not application builds.
- The Settings update controls at the existing three interface sizes.

Actual downloaded release installation, Inno Setup compilation, app restart after a real update, and automatic publication against GitHub remain unverified. The source changes do not remove the original compiler and native redistribution-audit limitations. Full setup and release instructions are in `UPDATES.md`.
