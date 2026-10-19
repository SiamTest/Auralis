# Native dependencies

Run `pwsh ./tool/build-tdlib.ps1` to build TDLib 1.8.68 from the pinned source revision. It places `tdjson.dll` and its OpenSSL/zlib dependencies here. CMake copies them to `native/` beside the Windows executable. DLLs and local build trees are ignored by Git. Never place API credentials or sessions in this directory.

The media_kit Windows audio plugin supplies `libmpv-2.dll` beside the executable. Its source recipe and exact archive are documented in `THIRD_PARTY_NOTICES.md`.

No TDLib DLL is included in this source delivery. The separately downloaded Python-wheel TDLib used for local smoke testing is confined to the task's scratch directory. CI builds TDLib from source instead.
