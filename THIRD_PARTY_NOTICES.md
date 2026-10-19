# Third-party notices and native provenance

Auralis's original source is AGPL-3.0-or-later. Third-party components retain their own terms. This source delivery contains no PixelPlayer or mpvRx app source/assets and contains no native DLLs.

| Component | Terms / source |
|---|---|
| Flutter and generated Windows host | BSD-3-Clause; [Flutter](https://github.com/flutter/flutter), retained text in `docs/FLUTTER-LICENSE.txt`. |
| Dart SDK | BSD-style SDK notices; distributed by Flutter. |
| media_kit 1.2.6+auralis.2 and media_kit_libs_windows_audio 1.0.9 | MIT; [media-kit](https://github.com/media-kit/media-kit), retained text in `docs/MEDIA-KIT-LICENSE.txt` and `third_party/media_kit/LICENSE`. The vendored runtime includes Windows COM/shutdown fixes documented in `third_party/media_kit/AURALIS_PATCH.md`; upstream copyright headers are retained. Native libraries have separate terms. |
| ffi 2.2.0, path 1.9.1, path_provider 2.1.6 | BSD-3-Clause; [Dart native packages](https://github.com/dart-lang/native), [Dart core packages](https://github.com/dart-lang/core), [Flutter packages](https://github.com/flutter/packages). Dart/Flutter include package notices in the generated Flutter license asset. |
| package_info_plus 10.2.1, crypto 3.0.7 | BSD-3-Clause; [plus_plugins](https://github.com/fluttercommunity/plus_plugins), [Dart core](https://github.com/dart-lang/core/tree/main/pkgs/crypto). Used for installed-version metadata and update integrity. Transitive package notices are included by Flutter. |
| TDLib 1.8.68 | Boost Software License 1.0; full text in `docs/TDLIB-LICENSE.txt`. Build revision: `a94b83d67ab4c8397c6245e541b31a4131ea2f79`. |
| OpenSSL and zlib | Dependency-specific licenses copied by `tool/build-tdlib.ps1` into `native/licenses/`; versions/build inputs follow vcpkg revision `664933b8d385dfc01f4e0cdff4c7c74e71f6a740`. |
| libmpv and FFmpeg native playback | Build-dependent GPL/LGPL and dependency terms. Do not infer native binary licensing from the MIT wrapper. See below. |

## Playback binary selected by the pinned plugin

The package's Windows CMake manifest downloads:

- Archive: `mpv-dev-x86_64-20230924-git-652a1dd.7z`
- [Exact archive](https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z)
- Upstream plugin MD5: `cd738e16e2a19626d7cfa48801524f8c`
- Independently recorded SHA-256: `583af5a291fc99ae2641794ede1955c368eb4c19dc05f4f0a9c7f9456edeb6a8`
- [Native build recipe repository](https://github.com/media-kit/libmpv-win32-audio-build); inspected recipe revision `222494909872cafd8359ec7a1bfd1e062f4482c9`.
- [mpv licensing explanation](https://github.com/mpv-player/mpv/blob/master/Copyright), [FFmpeg licensing](https://ffmpeg.org/legal.html).

The archive contains a native DLL and headers, not a complete corresponding-source distribution. The build recipe repository includes external codec/library recipes. Its current HEAD alone does not establish every source revision/configuration used for the 2023 binary. **Complete corresponding native source and exact build-input verification remain unfinished.** Before public binary distribution, rebuild playback from fully pinned sources, preserve every dependency's required notices, provide complete corresponding source/build instructions under the applicable GPL/LGPL terms, and audit updates/security. A URL to a generic upstream HEAD or this app's source alone is insufficient.

The plugin's older native build is retained only for this development milestone and was exercised locally. No claim is made that its codec dependencies are current or cleared for production distribution. Replace it with an audited recent build before release.

## Test-only TDLib binary

Local native smoke tests used the `tdjson` 1.8.68 CPython 3.12 Windows x64 wheel from PyPI, checksum-verified as SHA-256 `0ce9a92d2ceaa2020eaf83af4310b411b015a340b26b35931aa873d690afd8bd`. Its DLLs remain outside this source deliverable in the task scratch folder; the Python binding is not a dependency of Auralis. The tested native library reported version 1.8.68. This does not verify the separate MSVC source-build script or its dependency versions.

CI builds TDLib from its pinned public source instead. Preserve its generated `native/build-manifest.json` and `native/licenses/` alongside any bundle. Flutter package notices are in the generated application `NOTICES` asset and accessible through Settings → Licenses; native notices are also supplied as files by the packaging script.

## Optional lyrics service

[LRCLIB](https://lrclib.net/docs) is an optional HTTPS service, not bundled app code or a runtime package dependency. Auralis independently implements its API client and line-timed LRC parser. Online lookup is explicitly requested in the lyrics view and sends song title/artist/duration only. Retrieved or pasted song lyrics retain their respective owners' rights; the Auralis source license does not relicense that content. Only original synthetic lyric text is included in tests/screenshots. No PixelPlayer code or assets are reused.
