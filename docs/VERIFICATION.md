# Verification record — Windows x64, 19 October 2026

Local environment: Windows 11 24H2 (10.0.26100.9550), Flutter 3.47.1 (framework `6655482ec0`), Dart 3.13.1. The original records below describe local tests. The subsequent GitHub Actions failure and local shutdown regression results are recorded at the end.

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

The first GitHub Actions run subsequently compiled TDLib and the Flutter Windows app, but failed during native shutdown before packaging. No complete build/package/publish run has passed yet. ZIP/source/checksum packaging and tag matching have separately been tested with fixture files. A live Telegram account login, chat pagination against Telegram, actual channel downloads, real-network buffer recovery/seeking, and fresh-machine installation remain required. Complete the native license/source and security audit before public binary release. Do not treat this record as evidence those outstanding checks passed.

## Release and updater follow-up

Final local check: `flutter analyze --no-pub --fatal-infos` found no issues, and `flutter test --no-pub --reporter expanded` passed **all 22 tests**. This includes the real helper test and fixture packaging test described below. All three PowerShell scripts parsed successfully; the updated workflow structure was parsed separately.

Configured public update repository: `SiamTest/Auralis`. The GitHub connection reports READ permission. The repository was initially empty; the user subsequently uploaded the source and ran CI. This task has not pushed source, started CI, or published a release.

New automated checks cover:

- Numeric stable-version ordering; rejecting prerelease/malformed tags, older releases, drafts, incorrect asset names/URLs, missing digests and invalid sizes.
- Download byte counts, digest validation, tampered/truncated files, safe GitHub CDN redirects and blocking other hosts, rate limits, missing releases, and preference persistence.
- Rehash before install, helper-before-exit ordering, and cancelling the helper if application exit is cancelled.
- A **real hidden Windows PowerShell helper** invoked with a harmless `.cmd` installer stand-in: it waited for a separate process to exit, verified the file, passed arguments/paths containing spaces, and rejected an incorrect hash. It installed no software. This test found and fixed reliance on PowerShell module discovery; helper hashing now uses .NET directly.
- Real PowerShell ZIP/source/checksum packaging with temporary marker files and a temporary Git repository, validating pubspec-based names and rejecting a mismatched tag. The fixture's EXE/DLL marker files were never executed and are not application builds.
- The Settings update controls at the existing three interface sizes.

Actual downloaded release installation, Inno Setup compilation, app restart after a real update, and automatic publication against GitHub remain unverified. The source changes do not remove the original compiler and native redistribution-audit limitations. Full setup and release instructions are in `UPDATES.md`.

## GitHub failure and Windows shutdown follow-up

Inspected [run 39206678100](https://github.com/SiamTest/Auralis/actions/runs/39206678100), commit `634f23b802888603c18e18bb2679de8e0eb2c957`. Analysis, automated tests, pinned TDLib compilation, and Flutter Windows release compilation passed. Native smoke playback checks printed successfully at 06:42:25 UTC; libmpv crashed at 06:42:30 UTC with access violation `0xC0000005`. The overall native step failed; a printed report did not mean a successful process exit. No installer was generated by that run.

The included media_kit Windows teardown patch removes its deferred five-second destruction and awaits native termination before releasing the callback. Details, affected files and application instructions are in `NATIVE_SHUTDOWN_FIX.md`.

Final local verification of the patch:

- Locked dependency resolution succeeded with vendored media_kit 1.2.6+auralis.1.
- `flutter analyze --fatal-infos`: no issues. Vendored upstream code is excluded from application style lints; the patched runtime was compiled and exercised by the native smoke processes.
- `flutter test`: all 22 tests passed, including responsive UI, settings, Telegram/proxy behavior, updater integrity/helper and packaging fixtures.
- `dart run tool/native_smoke_repeat.dart <libmpv-2.dll> <tdjson.dll>`: all three child processes exited naturally with code 0, each after four player lifecycles (12 total). Each passed real native DPAPI, TDLib initialization/close, muted local WAV playback/seeking, and loopback playback/seeking with a simulated Telegram cache.
- Updated workflow YAML parsed successfully: 13 build steps and a tag-only publisher dependent on successful build.

The original failure was not reproduced by the unpatched local smoke run. These results support the shutdown fix but do not establish that the GitHub-specific crash is resolved: the patched commit has not run there. The connection remains READ-only. No new executable/installer was built locally, no remote commit was pushed, and no release was published.

## TDLib build cache follow-up

The workflow now uses pinned `actions/cache/restore` and `actions/cache/save` to reuse the compiled TDLib/dependency DLLs, notices and manifest. An exact hit skips compilation; a miss builds from the existing pinned source. Saving happens immediately after native compilation succeeds, before later app-build/test/package steps. Cache keys include the Windows image version and build-script/workflow hashes; there is no prefix fallback.

Verification for this configuration-only change:

- Official `actionlint` 1.7.12 Windows x64 executable, downloaded from its project release and SHA-256 checked against its release checksum file: workflow passed without findings.
- Parsed YAML and checked restore/build/save order, matching cache payload/key, miss-only compilation/save, required source/image invalidation, unconditional native smoke tests and preserved tag-only publishing.
- Executed the actual new PowerShell image-identification block with a valid fixture value: wrote the expected step output. Missing image metadata failed explicitly without producing an ambiguous key.
- Confirmed GitHub's Windows runner environment configuration exports `ImageVersion`.

No application source or native code changed in this follow-up; the previous app/native checks were not rerun. Real cache upload/download, a cache hit and speedup remain unverified on GitHub because the API connection has READ permission and no authenticated Chrome session is exposed to the browser tool. The currently running old workflow cannot adopt this change midway through. Its outputs were not cached by that old workflow. The first new run needs to build TDLib to seed its cache.

## Persistent native failure and COM lifetime follow-up

The user subsequently supplied a strict smoke-process failure inside `_terminateDestroy`, again at native offset `0x13fa81`. The earlier callback-ordering fix was insufficient. Native disassembly/string/import analysis maps that operation to WASAPI hotplug notification unregistration. See `NATIVE_SHUTDOWN_FIX.md` for evidence and primary source links.

Current vendored runtime: media_kit `1.2.6+auralis.2`. Each Windows player retains an OS-managed MTA usage cookie before creation and releases it only after native destruction and callback closure. HRESULTs and native initialization failures are checked. The strict smoke test additionally queries `audio-device-list` explicitly and prints shutdown-cycle progress; it still requires natural exit code 0.

Local follow-up checks: static analysis reported no issues; all 22 existing app/UI/Telegram/proxy/update/packaging tests passed. The final native repeat run passed all three processes, four player lifecycles each (12 total), including device monitoring, decoding, seek, loopback proxy and shutdown. Tests used the same pinned libmpv binary, real Windows COM lifetime APIs, and the test TDLib binary described in the notices.

The original and intermediate unpatched local probes also exited cleanly. The exact CI crash remains unreproduced locally; this follow-up is a targeted fix awaiting the actual GitHub runner, not a claim that CI now passes. Full app compilation, installer creation/installation, audible device output and live Telegram playback remain unverified here. TDLib caching is included. No remote commit or release was made with the READ-only connection.

## Successful Windows CI and stable publication follow-up

Verified [run 39232305284](https://github.com/SiamTest/Auralis/actions/runs/39232305284) at commit `dc73a962847272f45d5b0faa83f53718480048b1`: analysis, tests, source-built TDLib, Flutter Windows release compilation, strict native repeat tests and Inno Setup packaging all succeeded. The non-expired `auralis-windows-x64` artifact was 58,469,012 bytes. The TDLib cache was saved successfully (12,851,116 bytes); the first native compilation took 53 minutes 20 seconds. `publish` was skipped because the old workflow required a version tag and this was a `main` push. No releases existed when the publishing follow-up was inspected.

The current revision publishes successful `main` builds automatically, deriving the stable tag from `pubspec.yaml` and creating it at the tested checkout commit. It also supports matching explicit version tags, marks releases with `prerelease=false`, verifies every server asset digest before publishing, serializes publishers and never replaces a published version or moves an existing tag. Older versions do not displace a newer stable Latest. Other branches, PRs and source/version mismatches cannot publish.

Local verification of this release-only change:

- All **36 tests passed**, including 14 new publisher tests executing the actual PowerShell publisher with a process-local fake GitHub CLI. Coverage includes main/tag publication, tested tag creation, exact commit validation, same-version immutability, later API pages, permission errors, mismatched existing tags, existing prereleases, draft recovery, digest failure, older-version Latest protection, feature branches and PR rejection.
- Static analysis found no issues. Official `actionlint` accepted the updated workflow, and PowerShell parsed the publisher/fixture without errors.
- Workflow structure checks verified dependency on successful build, main/tag gating, serialized publishing, limited write permissions, preserved exact-match TDLib caching and unconditional native smoke tests.
- Actual read-only GitHub CLI queries verified paginated release-list parsing and exact-tag lookup. No mock call contacted or mutated GitHub.

The app/native implementation is unchanged from the successful CI source; only publishing configuration/script, tests and documentation changed. This edit invalidates the workflow-hashed TDLib cache once. Actual tag creation, asset upload and publication still require GitHub verification: the connection is READ-only, so no commit, tag or release was created by this task. Installer installation, audible hardware output, live Telegram authentication/playback, real app updates and the native corresponding-source/security audit remain outstanding.

## Original-quality streaming requirement

Reviewed the selected-message file ID, TDLib download/cache reads, HTTP proxy and native playback path. The app relays original file bytes to the decoder without an encoder, bitrate cap, adaptive-quality selection or alternative-file fallback. The existing implementation already met this transport requirement; no quality mode or conversion layer was added.

Strengthened the real localhost HTTP regression test: a complete 600,000-byte synthetic original spans multiple TDLib reads after simulated buffering; its streamed length and SHA-256 must equal the source. MIME type, original file ID, exact seek range, suffix, HEAD and rejection behavior are checked in the same test. All five focused streaming tests passed. The TDLib cache responses remain simulated; this is byte-integrity evidence for the transport, not a live Telegram account test or a measurement of decoded hardware output.

The original source file's encoding quality cannot be improved by transport. Bit-perfect Windows/DAC output, exclusive audio mode, actual audible output and live-account playback remain unverified. The source policy and limits are documented in README.md. The runtime change in this follow-up is a documentation comment only; native playback/release workflow behavior is unchanged.

## Original Windows icon follow-up

Replaced Flutter's stock `windows/runner/resources/app_icon.ico` with an original violet A/play mark, authored as `assets/branding/auralis.svg`. The same ICO is now selected by Inno Setup. The existing executable resource, window icon and Start menu target already refer to that application icon. Version is now `0.1.1+2`, including Telegram client metadata and fallback About strings, so the artwork can ship as a newer stable update.

Verification for this change:

- Visually inspected the rendered artwork. Parsed all ten ICO entries and decoded their PNG frames at 16, 20, 24, 32, 40, 48, 64, 96, 128 and 256 px; each has the expected dimensions and transparency.
- The actual Windows `LoadImageW`/`GetIconInfo` APIs successfully loaded all ten sizes as 32-bit icon bitmaps. This checks native icon compatibility, including the 256 px PNG frame.
- Static analysis found no issues; all **36 tests passed**. `tool/package.ps1 -ValidateOnly` returned `0.1.1`.

The new executable and installer have not been compiled or launched locally because the Visual Studio toolchain is still unavailable. The earlier successful CI build predates this artwork. A rebuild/reinstall is required; Windows may retain an old pinned shortcut's cached icon until it is unpinned and pinned again. No remote source or release was changed through the READ-only connection. Playback, updater logic, workflow and TDLib source/cache settings were not changed by the icon fix.

## Display name capitalization

Changed the navigation header from `auralis` to `Auralis`, matching the existing window title, application title, About dialog and installer. The existing responsive UI test passed at all three recorded sizes, and its refreshed library preview was visually checked. This is a display-text-only correction; package identifiers, executable filenames, stored data and release asset names retain their existing values. No new Windows executable was built for this correction.

## Channel-only Telegram browser

Version `0.1.2+3` exposes only TDLib chats whose type is `chatTypeSupergroup` with `is_channel=true`, using [TDLib's explicit channel flag](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1chat_type_supergroup.html). Private/bot conversations, basic groups, ordinary supergroups, secret chats and missing channel metadata are excluded at ingestion. Title updates can rename an existing channel but cannot insert a hidden chat. Main and archived chat lists still load incrementally; the visible list and search contain channels only. Search, counts, empty states, header, channel icons, sign-in description, browse error and back navigation now refer to channels.

All **37 tests passed**, and static analysis found no issues. The new fake-transport regression covers mixed chat types, unknown/missing flags, title updates for excluded/unknown chats, channel renaming/sorting, main/archive load requests, newly loaded channels/groups, replacement metadata and logout clearing. The existing responsive UI test additionally checks the connected channel-only empty state and labels at all three sizes. Its first attempt failed because the test mutated authorization state without notifying the UI; the fixture now uses the service's notification path, and the complete rerun passed.

These are simulated Telegram updates, not a live-account test. No new executable or installer was built locally, and no remote source or release was changed. This update only filters Auralis's browser; it does not delete or modify Telegram conversations. On an early page containing no channels, use Load more to continue loading the underlying lists. Playback and the native/TDLib cache workflow are unchanged.

## Selected-channel Library and Telegram artwork

Version `0.1.3+4` changes Telegram into a channel-selection screen and Library into the combined music collection from those selections. Selected IDs/titles persist in settings. The Library scans both audio and document filters automatically to the end of every selected channel's history, ignores non-audio documents, deduplicates message IDs, shows incremental results/partial errors, and invalidates late responses after selection changes, sign-out or disposal. Pagination uses each response's own cursor rather than shared mutable service state. Empty filtered document pages do not stop older-page loading; a repeated cursor reports a partial error rather than looping forever. Current TDLib pagination semantics were checked against its [searchChatMessages reference](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1search_chat_messages.html).

Local-file import, Ctrl+O, path-backed playback, stored local references and the file-selector dependency are removed. Legacy local-path settings are ignored; music files are never deleted. Locked dependency resolution removed the unused picker and its eight transitive packages, and regenerated the Windows plugin registration. The native playback/TDLib versions and workflow/cache configuration remain unchanged.

Track metadata now retains Telegram cover-thumbnail file IDs, selecting the largest supplied variant; channel metadata retains photo file IDs and handles rename, photo-change and photo-removal updates. Artwork appears in track rows, queued rows, Now Playing, the player bar and channel selection. The image loader deduplicates requests, bounds its request cache to 128 entries, uses low-priority TDLib downloads, checks completed local files, and invalidates results on sign-out. Flutter decodes at bounded display sizes; failed downloads and decoding errors retain generated artwork. Library Refresh retries artwork. TDLib's [audio cover fields](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1audio.html) and [downloadFile completion/priority behavior](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1download_file.html) were verified in its primary documentation.

All **51 tests passed**. Coverage added in this follow-up:

- Multi-channel selection/persistence, automatic restart reload, complete audio/document pagination, empty non-audio pages, duplicate messages, deselection, partial failures, non-channel saved IDs, repeated cursors, save failure rollback, sign-out and disposal with in-flight requests.
- Cover/document-thumbnail parsing, low-priority shared image downloads, channel photo updates/removal, missing/incomplete/failed downloads, retry, bounded cache and sign-out invalidation.
- UI integration selects two channels, opens their combined Library, searches by channel, enqueues/plays via the real loopback proxy and fake audio backend, verifies channel photos plus Library/Now Playing/player-bar image widgets, and deselects a source. Responsive checks cover 1280×800, 760×650 and 520×560. Real Flutter file-image decoding uses the original app icon as a local fixture; `docs/screenshots/channel-library.png` is explicitly fixture data, not live account evidence. Image tests flush real file callbacks after widgets mount; early fixture attempts staying on placeholders were corrected before the successful run.

The earlier Windows CI build predates this revision. A new Windows executable/installer has not been compiled or launched locally, and no source or release was pushed. Live-account indexing, actual channel photos/covers, rate-limit behavior, very large libraries, hardware output and installation remain unverified. Full-size embedded cover extraction and live message-change monitoring are not implemented: absent Telegram thumbnails keep generated artwork, and Refresh discovers newly posted music. Channel choices persist across sign-out; tracks clear until connected, and saved channels are resolved and type-checked through TDLib before indexing. Queued/playing tracks are independent of later channel deselection. The previous native redistribution audit limits remain.
