# Android build and use

Auralis now shares its Flutter UI and Telegram library/player features between Android and Windows. The Android app ID is `app.auralis.auralis`; minimum Android is **7.0 / API 24**. The default APK is **ARM64**, suitable for the Redmi Note 10 Pro. x86_64 is available for emulator testing. There is no 32-bit APK in this milestone.

## Separate GitHub Action

Commit the complete project, including the new `android/` folder, to your repository. Open **Actions → Android APK build**. It runs independently on pushes, pull requests and manual dispatch, with a manual architecture selector. Windows keeps `.github/workflows/windows.yml` and its existing compiled TDLib cache. Neither workflow depends on the other finishing.

The Android workflow installs Java 17, Flutter 3.47.1, Android SDK 36 / build tools 36.0.0, NDK 28.2.13676358 and host build tools. It resolves the lockfile, runs analysis and tests, builds pinned TDLib/OpenSSL for the selected ABI, compiles an APK, verifies its signing and required native libraries, checks all native ELF load segments for 16 KiB alignment, and uploads the APK, SHA-256 checksums and native provenance as an Actions artifact. The initial TDLib build is substantial; later compatible runs reuse its ABI-specific cache. Tests and the final APK build always run, including on cache hits.

Download **auralis-android-arm64-v8a-development** or **auralis-android-arm64-v8a-release** from the successful run's **Artifacts** area, extract it and install its APK on your phone. This workflow builds artifacts only. It does not publish a GitHub Release, replace Windows assets or upload to Google Play.

## Signing and upgrades

With no signing secrets, CI produces a **development/debug APK**, signed by the runner's debug key. This is for testing. Different clean runners can generate different debug keys; an APK with a different key cannot update an existing installation. Preserve/export your app data before uninstalling a development build. Do not use development keys for stable distribution.

For release APKs, create one private signing key, keep it securely and reuse it for all updates:

```bash
keytool -genkeypair -v -keystore auralis-release.jks -alias auralis -keyalg RSA -keysize 4096 -validity 10000
```

Add all four **repository Actions secrets**:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the complete private `.jks` file, as a single line |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Alias, e.g. `auralis` |
| `ANDROID_KEY_PASSWORD` | Key password |

No secrets means a development APK; a partially configured set fails explicitly. Pull requests always build development APKs without release signing secrets. Signing files are temporary, ignored by Git and removed in an `always()` cleanup step. Release builds never silently use debug signing. Do not commit keys, `key.properties`, Telegram credentials, sessions or local SDK paths.

## Android behavior

- The same Library, Telegram channel selection, covers, queue, playlists/favorites/recent music, lyrics, repeat/sleep timer, listening stats, export and Backup & Restore are available in the responsive interface.
- `audio_service` provides a media playback foreground service and notification/lock-screen/headset controls. It keeps the Flutter engine available while audio plays with the screen off. Calls/audio interruptions and headphone removal pause playback; it does not resume unexpectedly after a call. Swiping the app from Recents stops playback and clears the queue. Android force-stop and manufacturer battery restrictions can still stop the app.
- Credentials and the TDLib database key are encrypted with a non-exportable AES-256-GCM key in Android Keystore, with a fresh IV and authentication tag for every write. App data stays in Android's private support directory. OS backup/device-transfer of this data is disabled because the key is tied to the installation/device. Login codes and two-factor passwords are never saved.
- Stats are flushed when the app pauses as well as at the existing checkpoints. Pausing the UI does not stop background music. Process death may still lose the latest unsaved samples; playback queue/timers are session-only.
- Export and Backup & Restore use Android's system **Create document / Open document** picker, supporting Downloads and document providers without broad storage permissions. Selected document URIs are read/written via the content resolver on a worker thread. Local automatic recovery copies still use app-private files. Backup size/schema/integrity validation and confirmation are shared with Windows. Backups exclude credentials, keys, music files and sessions. Restoring collections on another device still requires signing into the appropriate Telegram account and selecting accessible source channels.
- The Windows EXE installer/updater is disabled on Android. Install a newer APK signed with the same private key to upgrade; existing app data remains in place during an ordinary same-key upgrade. This milestone does not add an Android self-updater, Play Store upload or local music importing.

## Local build on Linux

Install Java 17, Flutter 3.47.1, Git, a C/C++ compiler, CMake, Ninja, Perl, gperf, OpenSSL and zlib development headers, plus Android command-line tools. Set `ANDROID_HOME` to your Android SDK. Use a CI environment variable in automation so Flutter does not need to detect the host through a cloud metadata service.

```bash
sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
flutter pub get --enforce-lockfile
flutter analyze --no-pub --fatal-infos
flutter test --no-pub --reporter expanded
python3 -m unittest discover -s tool -p test_android_tools.py
bash tool/build-tdlib-android.sh arm64-v8a
flutter build apk --debug --target-platform android-arm64
python3 tool/verify-android.py build/app/outputs/flutter-apk/app-debug.apk arm64-v8a
```

For a local release, create the ignored `android/key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`, using an absolute keystore path or a path relative to `android/`. Then build with `--release`. Keep the same application ID and signing key across upgrades, and increment `pubspec.yaml` for each app update.

To test on a connected x86_64 emulator, build TDLib for x86_64 and use `--target-platform android-x64`. The native Android Keystore test can then run with `cd android && ./gradlew connectedDebugAndroidTest -Ptarget-platform=android-x64`. This is an actual device/emulator test; host bridge tests alone do not verify Android cryptography or hardware playback. See VERIFICATION.md for what was run for this delivery and THIRD_PARTY_NOTICES.md for native distribution limits.


### CI SDK command-line setup

The Android workflow explicitly runs the commit-pinned android-actions/setup-android action after Java setup and before invoking sdkmanager. This provisions the command-line tools, accepts SDK licenses and adds sdkmanager to PATH; the following step installs the pinned Android 36/build tools/NDK packages. The apt-get output in the reported failure was successful; exit 127 came from the missing sdkmanager command. This is a CI-only correction; the source version stays 0.1.21+22. Commit the complete corrected source and run the Android APK build workflow on that commit; rerunning the previous commit uses its old workflow.
