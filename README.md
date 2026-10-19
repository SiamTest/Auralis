# Auralis — Windows x64 music player

An independently authored Flutter desktop player with a compact violet/charcoal interface, a Library combining music from selected Telegram channels, and a playback queue. Design references: [mpvRx](https://github.com/Riteshp2001/mpvRx); Telegram feature reference: [PixelPlayer](https://github.com/PixelPlayerHQ/PixelPlayer). This is a separate project, with no upstream application code, branding, screenshots, icons, or other assets copied.

![Test-rendered library](docs/screenshots/library.png)

## Milestone status

**CI-built Windows milestone; installation and live Telegram playback remain unverified.** The build job in [GitHub run 39264104723](https://github.com/SiamTest/Auralis/actions/runs/39264104723) passed analysis/tests, TDLib cache migration, Flutter Windows compilation, native smoke tests and installer packaging for v0.1.3. Publishing failed afterward; this source includes the repair plus embedded-cover support and Library sorting. See [verification](docs/VERIFICATION.md) for exact results and limits.

The local executable build is blocked because Visual Studio C++ Build Tools are absent. The source ZIP contains no EXE or installer. [Run 39264104723](https://github.com/SiamTest/Auralis/actions/runs/39264104723) built version `0.1.3+4`, passed analysis/tests and native smoke checks, compiled its installer and reused the TDLib cache without compiling it again. Only publishing failed: a published-only tag lookup could not inspect its draft. Current version `0.1.7+8` retains the numeric-ID draft lookup repair and adds embedded artwork, Library sorting broader build caching and the Windows update-exit repair; these changes have local regression coverage and await a new GitHub build. The existing `v0.1.3` tag is preserved. See [release instructions](docs/UPDATES.md) and [shutdown fix](docs/NATIVE_SHUTDOWN_FIX.md).

Implemented:

- Original violet A/play app icon, with Windows taskbar/executable, Start menu and installer branding. Editable artwork is in [assets/branding](assets/branding/README.md). Version `0.1.1+2` carries the icon replacement; rebuild and reinstall to apply it. If a previously pinned shortcut retains Flutter's cached icon, unpin it and pin the newly installed Auralis executable again.
- Responsive Library, queue, and now-playing pages; persistent channel selections, volume and reduced-motion preference. Select one or more channels in Telegram, then search their combined Library by title, artist or channel. Use the sort button beside Library to order by newest/oldest Telegram post, title, artist or shortest duration. The choice persists between launches; changing it does not reorder the queue. Local-file importing/playback is removed; old local-path preferences are ignored without deleting audio files.
- Music covers in Library, queue, Now Playing and the player bar: Telegram thumbnails, tiny previews and embedded MP3/FLAC/M4A artwork. Channel photos appear beside selection. Artwork loads on demand at low priority with bounded requests; missing/failed images use original procedural artwork. No external artwork search is used. See [artwork limits](#telegram-artwork).
- Queue add, reorder, shuffle upcoming tracks, previous/next, repeat queue, play/pause, seek bar and volume. Media keys work while the app has keyboard focus. No global media-key registration.
- TDLib JSON bridge on a dedicated isolate; request correlation, timeouts, ordered updates, and graceful close. Phone, login code, and 2FA forms, plus email verification forms when Telegram requests them.
- Main and archived accessible channels only, with selection checkboxes. The Library automatically follows every older audio/document page from each selected channel, ignores non-audio documents, deduplicates messages and shows progress/partial errors. Changing selection or signing out invalidates pending results. Private chats, bots, basic groups and non-channel supergroups are excluded, including after title/photo updates. Browsing does not join channels or bypass permissions.
- Private loopback HTTP endpoint with an unpredictable capability URL; full/partial/suffix byte ranges, HEAD, download-prefix checks, buffered reads, range cancellation and stalled-download errors. Native seeking may be served from libmpv's buffer or trigger another TDLib range.
- Windows DPAPI-encrypted API credentials and random TDLib database encryption key. Codes, phone numbers, and 2FA passwords are not saved by Auralis. Native diagnostic logging is suppressed. Runtime data and native DLLs are ignored by Git.
- Automatic stable-release update checks, verified installer downloads, and user-confirmed install/restart, configured for [SiamTest/Auralis](https://github.com/SiamTest/Auralis). Settings includes a manual check and an automatic-check preference. The updater finishes audio/Telegram cleanup before requesting Windows exit, avoiding the premature cancel acknowledgement that stopped the helper in v0.1.3. Existing affected installs need one manual update; see [update/release instructions](docs/UPDATES.md).
- Automated tests, Windows build workflow, versioned ZIP/source/installer packaging, and automatic stable GitHub Releases from successful `main` builds or matching version tags, with checksum verification.

Not implemented or not verified:

- **Live account authentication and real Telegram music playback are unverified.** No API ID/hash, phone number, login code, or 2FA password was provided or used. Authorization tests use a fake TDLib transport; native TDLib was tested before account initialization. Buffered proxy tests simulate the TDLib file cache. They do not prove Telegram network behavior.
- Account creation, QR login, Premium-required verification, recovery flows, and automatic restart after logout are not implemented. The UI explains these states; use the official Telegram app where required. Restart Auralis after logout.
- No folder scanner, tag editor, album/artist index, playlists on disk, persisted queue, lyrics, equalizer, crossfade, global shortcuts, system media controls, tray mode, installer signing, or forced background installation.
- No cache-size preference or automatic eviction policy yet. TDLib media cache files are plaintext in the user's application-data directory; the database key protects the TDLib database, not downloaded audio. Logout revokes the Telegram session; it does not promise secure deletion of cached media or API application credentials.
- No fresh-machine installer test, signing certificate, performance profiling, high-DPI hardware audit, screen-reader audit, or public distribution readiness claim. The bundled playback dependency resolves to an older native build; refresh and audit it before production use. See [notices](THIRD_PARTY_NOTICES.md).

## Streaming audio quality

Telegram playback uses the original file ID from the selected message. The streaming proxy passes its file bytes unchanged to libmpv: no re-encoding, lossy conversion, bitrate cap or lower-quality fallback. Download priority, buffering and byte-range seeking affect when bytes arrive, not their encoded quality. A slow download buffers or reports a stalled-transfer error rather than switching to a lower-bitrate copy.

This preserves the quality of the file supplied in Telegram; it does not restore detail already absent from that source. Volume adjustment and the Windows/audio-device output path are separate from file transport. Bit-perfect DAC output or exclusive-mode playback is not implemented or verified. The regression test checks a complete multi-chunk stream's SHA-256 against its simulated original and checks seek ranges exactly; live-account playback remains unverified.

## Dependencies and build

Use **Windows x64**, Flutter **3.47.1** / Dart **3.13.1**, Git, PowerShell **7.4+**, CMake, and **Visual Studio 2022** (or Build Tools 2022) with **Desktop development with C++**, the MSVC x64 toolset, and Windows SDK. Install these tools using their official installers, then check `flutter doctor -v`.

Pinned Dart dependencies and their transitive versions are in `pubspec.yaml` and `pubspec.lock`: Flutter, media_kit 1.2.6+auralis.2 (vendored MIT runtime with Windows COM/shutdown patches), media_kit_libs_windows_audio 1.0.9, ffi 2.2.0, path 1.9.1, path_provider 2.1.6, package_info_plus 10.2.1, and crypto 3.0.7. TDLib is built separately; no third-party Dart Telegram wrapper is used. Keep `third_party/media_kit` in Git with the app; its patch and original license are included there.

From this directory:

```powershell
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test --reporter expanded
pwsh ./tool/build-tdlib.ps1 -Jobs 2
flutter build windows --release
dart run tool/native_smoke_repeat.dart `
  "$PWD/build/windows/x64/runner/Release/libmpv-2.dll" `
  "$PWD/native/tdjson.dll"
pwsh ./tool/package.ps1
```

TDLib's first build can take a long time and several GB of disk space. The script pins TDLib and vcpkg revisions, builds OpenSSL/zlib/gperf through vcpkg, and builds `tdjson.dll` with MSVC. Start with two parallel compiler jobs to limit memory use. It writes only its generated `.native-build/` tree, `native/` binaries, license texts, and build manifest. Neither upstream player is cloned or modified.

GitHub Actions caches the compiled TDLib DLLs, dependency DLLs, license files and build manifest immediately after a successful TDLib build or compatible legacy-cache restore. The stable key includes the Windows runner image version and native build-script hash; UI and release-workflow edits do not invalidate it. An audited migration can reuse the existing v1 cache from the same image with the exact unchanged builder, then save it under the stable v2 key. Changed native inputs/images and unavailable caches still require compilation. See [cache details](docs/UPDATES.md#tdlib-build-cache).

The workflow also retains Flutter SDK and locked Pub package caching, and now caches Windows/CMake intermediates (including the libmpv download), Flutter/Dart compilation data, and native hook output. Compatible builds warm-start from the previous source revision; source changes receive a new cache entry. Keys separate Windows runner image, Flutter SDK, dependency lock, Windows native sources and vendored runtime. The final Release bundle is excluded and rebuilt; analysis, tests, native smoke checks, packaging and asset verification always run. If compiled TDLib is unavailable, vcpkg downloads and ABI-checked binary packages (OpenSSL/zlib/gperf) can be reused. Native dependency caches are saved even if a later TDLib compilation fails. See [build cache coverage and limits](docs/UPDATES.md#additional-build-caches).

Run the app with `flutter run -d windows` after native setup, or launch `build/windows/x64/runner/Release/auralis.exe`. Keep **the entire Release directory** together. The executable depends on Flutter's DLL/data files, `libmpv-2.dll`, and `native/tdjson.dll` plus its dependent DLLs. End-user machines also need the Microsoft Visual C++ 2015–2022 x64 runtime. The optional installer currently assumes it is installed.

`pwsh ./tool/package.ps1 -Installer` additionally requires Inno Setup 6 and produces an unsigned per-user installer. It requests no administrator privileges and preserves application data during uninstall. Neither packaging mode has been tested with a built executable in this environment.

Packaging derives asset names and the installer version from `pubspec.yaml`. Commit the source first: the source ZIP is produced from Git `HEAD`. Release tags must match the version exactly (currently `0.1.7+8` → `v0.1.7`). Packaging/tag validation has been tested with harmless fixture files; the current revision's installer compilation/installation is still outstanding.

## Connect Telegram

1. Create your own application at [my.telegram.org](https://my.telegram.org) and obtain its API ID/hash. Do not use someone else's credentials or commit yours.
2. Open Telegram in Auralis and enter the application ID/hash locally. Enter your phone number with country code, the code delivered by Telegram, and your 2FA password if requested.
3. Check the channels you want to include, then choose Open Library. Their music appears together as older audio and audio-document pages load automatically. Use Load more in Telegram to discover more main/archived channels. Your selection is saved and loads again after sign-in on subsequent launches.
4. In Library, search by title, artist or channel. Click a track to play the filtered list, or add individual tracks to the queue. Use Refresh to scan again for new music, retry partial failures and retry missing artwork. Deselect a channel in Telegram to remove its tracks from Library; already queued/playing tracks stay in the queue until you remove/clear them. Large channels can take time or hit Telegram rate limits; progress and partial errors remain visible.

If a Telegram-specific delivery/verification step is unsupported, the app shows that state. Existing Telegram account membership/access rules apply. This app has no affiliation with Telegram, mpvRx, or PixelPlayer.

## Telegram artwork

Audio messages first try the largest supplied Telegram album-cover thumbnail/cover variant; audio documents try their thumbnail. Tiny Telegram previews are shown while larger artwork loads. If a thumbnail is absent or unavailable, Auralis reads embedded artwork from ID3v2.2/2.3/2.4 (MP3), FLAC PICTURE blocks and MP4/M4A covr metadata. This is independently authored Dart code with no extra native library or external artwork lookup. Channel avatars use the small channel photo and follow photo-change/removal updates.

Only displayed items request artwork. The reader requests metadata ranges rather than full songs, skips MP4 audio payloads to reach tail metadata, caps metadata at 4 MiB, and parses away from the UI isolate. At most two cover jobs run together; up to 64 cover results and 128 channel/thumbnail request results are retained. Image decode sizes are bounded to the display. Metadata download requests use TDLib priority 1 and deadlines. For a file registered with the playback proxy, cover extraction uses already buffered bytes only: it never changes that file's active download offset. File-progress updates allow missing covers to retry as playback fills the cache. Refresh retries failed artwork. Original music bytes are unchanged.

Files with no picture, unsupported embedded-art containers (including Ogg/Opus/WMA), metadata exceeding the limit, inaccessible ranges or invalid image data retain a preview or the generated placeholder. The implementation cannot invent a missing cover. A provided thumbnail may be lower resolution than embedded artwork. Downloaded images/media remain plaintext in TDLib's application-data cache. The screenshot below uses original geometric test artwork embedded in a generated MP3 with **no Telegram cover thumbnail**; it verifies rendering with a fake TDLib transport, not the user's live channels.

![Selected-channel Library with fixture covers](docs/screenshots/channel-library.png)

## Storage and architecture

Windows application support data is resolved by `path_provider`, using the runner's company/product metadata. The app creates `settings.json`, `credentials.dpapi`, `session.lock`, and `telegram/database` plus `telegram/cache` there. The session lock prevents two Auralis processes from opening the same account database. Settings contain selected channel IDs/titles and preferences, never login secrets. Old local-file references are ignored and removed on the next settings save; source files are untouched. Channel selection remains a preference after sign-out, but music is cleared until connected and channels are checked through TDLib before indexing. Track metadata is rebuilt after launch rather than stored as a second persistent database. DPAPI vaults cannot be copied to another Windows user/machine and decrypted there. Secrets necessarily exist in process memory while being used; Dart strings cannot guarantee memory zeroization.

- `lib/app.dart`: UI, responsive navigation, channel selection, Library, artwork and Telegram forms.
- `lib/player.dart`: native audio backend and queue controller.
- `lib/telegram/td_transport.dart`: native TDLib receiver isolate and correlated requests.
- `lib/telegram/telegram_service.dart`: authorization, chat updates and music search.
- `lib/telegram/embedded_cover.dart`: bounded ID3/FLAC/MP4 picture extraction from file ranges.
- `lib/telegram/channel_library.dart`: selected-channel persistence, merged music indexing, pagination, cancellation and partial errors.
- `lib/telegram/stream_proxy.dart`: authenticated-by-capability loopback byte streaming.
- `lib/storage.dart`: Windows DPAPI vault and serialized atomic settings writes.
- `lib/updater.dart` / `lib/update_widgets.dart`: stable GitHub Release checks, checksum-verified downloads, update controls and graceful installer handoff.

Tests use generated audio and synthetic metadata only. Flutter UI previews are rendered test frames, not screenshots of a compiled Windows executable.

## GitHub Actions

Use this **project directory as the repository root** of [SiamTest/Auralis](https://github.com/SiamTest/Auralis), retaining `.github/workflows/windows.yml`. The workflow targets `windows-2022`, uses pinned action commits and Flutter 3.47.1, runs analysis/tests, builds or restores TDLib, builds Flutter Windows x64, runs native smoke tests, and uploads ZIP/installer/source/checksum artifacts. No Telegram secrets are needed. The current connection has READ permission; this task inspected the successful build but has not pushed the publishing follow-up.

Successful `main` builds automatically create the `vMAJOR.MINOR.PATCH` tag at the tested commit and publish a **stable release**, explicitly not a prerelease, after server-side asset digest verification. Matching version-tag builds also publish. Other branches/PRs create artifacts only. Already published versions are immutable: bump `pubspec.yaml` to a new stable version for each later release. The app checks stable releases automatically, downloads after a user click, and requires confirmation to install/restart. Installers remain unsigned. See [UPDATES.md](docs/UPDATES.md) for setup, publishing rules and test limits. The native corresponding-source/license audit and clean-machine installation check remain outstanding; a stable-release flag is not a production-readiness claim.

## License

Original Auralis application code and original procedural artwork: **AGPL-3.0-or-later**, copyright 2026 Auralis contributors. See `LICENSE`. The Flutter-generated Windows host retains Flutter's BSD terms. Choosing AGPL does not mean mpvRx code was reused. Any future reuse of mpvRx code must preserve upstream notices and satisfy AGPL requirements.

PixelPlayer's current proprietary code and assets are **excluded**. Its older MIT contribution history is not used as an exception. Third-party libraries retain their licenses; see [upstream audit](docs/UPSTREAM_AUDIT.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Include this source, dependency notices, and the required corresponding native source/build inputs when distributing a combined build; the present native dependency audit is not a clearance for public binary releases.
