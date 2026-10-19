# GitHub Releases and application updates

Configured repository: **[SiamTest/Auralis](https://github.com/SiamTest/Auralis)**. The user uploaded the source and the first workflow built TDLib and Flutter successfully, then failed during native smoke-test shutdown. The current GitHub CLI connection reports **READ** permission, so this task cannot upload the fix, trigger a workflow there, or publish a release. Commit the included [shutdown fix](NATIVE_SHUTDOWN_FIX.md) before starting another build; rerunning the old commit does not apply it.

## Release flow

1. Upload this project's contents as the repository root, including the hidden `.github` directory, `pubspec.lock`, and the license files. The main-branch push runs the Windows build/test/package job.
2. The job runs analysis and all tests, builds TDLib and the Flutter Windows app, and runs the native smoke test. It packages a portable ZIP, a per-user Inno Setup installer, an application source ZIP from the committed revision, and `SHA256SUMS.txt`. These are downloadable Actions artifacts for ordinary pushes/PRs/manual runs.
3. Push a stable tag that **matches `pubspec.yaml`**. Initial version: `v0.1.0` for `0.1.0+1`. A later release should first change the version to, for example, `0.1.1+2`, then tag the committed change `v0.1.1`.
4. Only tag builds enter the publishing job. It uses the workflow's `GITHUB_TOKEN` with `contents: write`; the build job keeps read-only permissions. The publisher creates a draft, uploads the assets, checks GitHub's SHA-256 asset digests against the local files, then publishes it as the latest stable release. A failed asset check leaves the draft unpublished. Already published tag assets are not replaced on a rerun.

Example after committing the complete initial source to `main` and completing the native distribution audit:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

Subsequent releases use the bumped matching version/tag. Branch names or tags such as `v0.1.1-beta` do not publish a stable release; mismatched or non-stable tags fail validation. The publisher validates the exact tag again before making any release changes.

Expected assets for `v0.1.1`:

```text
auralis-0.1.1-windows-x64.zip
auralis-0.1.1-windows-x64-setup.exe
auralis-0.1.1-source.zip
SHA256SUMS.txt
```

GitHub Actions and repository/org policies must permit the publish job's write token. No Telegram credentials or personal access token need to be committed or added to the app. **No complete workflow has passed yet: the first run stopped at native shutdown, before installer packaging. Actual installer compilation/installation remains unverified.** The local machine still lacks Visual Studio C++ Build Tools and Inno Setup.

## TDLib build cache

The workflow restores an exact cache of `native/*.dll`, `native/licenses/` and `native/build-manifest.json`, then skips `tool/build-tdlib.ps1` only when `cache-hit` is `true`. A cache miss runs the same pinned source build. The cache is saved immediately after that build succeeds, before the Flutter build, native smoke test or packaging: a later failure therefore does not discard the expensive TDLib build.

The key includes Windows 2022/x64/Release, GitHub's runner image version, and the hashes of `tool/build-tdlib.ps1` and `.github/workflows/windows.yml`. It changes when pinned TDLib/vcpkg revisions, build options, the workflow or the Windows image change. There are no prefix fallback keys that could restore incompatible binaries. The cache contains build outputs and notices only, with no Telegram account credentials, databases or downloaded music. Native smoke checks still run on cache hits.

The first run with this workflow needs to build and save the cache. Existing runs cannot adopt the change midway through, and old runs did not save a TDLib cache. GitHub controls cache scope, quotas and eviction, so a missing/expired cache causes another full build; no fixed speedup is promised. Ordinary app-source changes can reuse a matching cache. To force a rebuild, delete the matching entry under Actions caches or change the `tdlib-...-v1` key prefix.

This task can supply the edited workflow but cannot push it with the current READ-only GitHub connection. Replace the existing `.github/workflows/windows.yml` and commit it; keep the rest of the project. Actual GitHub cache upload/download and timing still require verification in CI.

Implementation follows the official [restore](https://github.com/actions/cache/blob/0057852bfaa89a56745cba8c7296529d2fc39830/restore/README.md) and [save](https://github.com/actions/cache/blob/0057852bfaa89a56745cba8c7296529d2fc39830/save/README.md) actions, pinned to that commit.

## Application update flow

- Auralis reads its installed version from Windows package metadata, using `package_info_plus`; it does not assume the source's version is the installed version.
- Automatic checks are enabled initially, run ten seconds after startup and every six hours while the app is open, and can be disabled in Settings. Settings also has a manual Check now button. No background scheduled task/service is installed.
- Checks use the configured public repository's latest stable GitHub Release. Drafts, prereleases, same/older versions, wrong asset names, missing SHA-256 digests, oversized files, and download URLs from another repository are not accepted.
- A new version shows a banner. Download retrieves that exact Windows x64 installer using HTTPS and verifies its byte count and the SHA-256 digest reported by GitHub. Redirects are limited to GitHub's specified download hosts. Incomplete or corrupt downloads are not executable candidates.
- Installation requires **Install and restart**, followed by confirmation. The file is hashed again before handoff. A hidden, local Windows PowerShell helper waits for Auralis's orderly audio/TDLib shutdown and process exit, hashes the file once more, then runs the per-user installer. The installer reopens Auralis after success. The helper cancels if the process does not exit within 90 seconds.
- Update errors do not replace the installed version. Helper/installer errors are written to `update-error.txt` in that update's download directory. A failed installer may require reopening Auralis manually. Settings, the DPAPI vault and Telegram database/cache remain in the user's application-data directory; they are not inside the installation folder or removed by an update.

This is **automatic update detection with user-confirmed installation**, not forced or silent replacement without the user's approval. Downloading also requires the user's click. The installer itself uses `/SILENT` after that explicit confirmation, with no reboot request or administrator elevation for a per-user install. Installing into an administrator-protected custom location is not supported by the updater.

Update files are stored under the app support directory's `updates/release-*` folders. Existing downloads/logs are retained; automatic cleanup and resuming a download across process restarts are not implemented. An interrupted download can be retried from Settings.

## Trust and current limits

GitHub's digest detects corrupted/mismatched downloads; it is **not** an independent publisher signature. A compromised repository/release publisher can publish a malicious installer and matching hash. Releases are currently unsigned; Authenticode signing and a separate signed update manifest are not implemented. Keep repository release permissions and GitHub accounts secure. The updater does not embed a GitHub token and supports public repositories only.

The default update source is `SiamTest/Auralis`. CI explicitly builds with `--dart-define=AURALIS_RELEASE_REPOSITORY=$env:GITHUB_REPOSITORY`, so an intentional fork uses its own repository; local builds default to SiamTest/Auralis. Changing the source requires rebuilding the app. Users cannot enter arbitrary executable URLs in Settings.

The original native playback corresponding-source/security audit remains outstanding. **Resolve the native source/licenses and codec updates before pushing a public release tag**: the tag workflow is configured to publish automatically after technical checks, and those checks are not a substitute for that audit. The application source ZIP contains this project, not complete corresponding source for every prebuilt native playback dependency. See `THIRD_PARTY_NOTICES.md`.

Primary documentation: [GitHub release API](https://docs.github.com/en/rest/releases/releases), [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create), [Inno Setup command-line parameters](https://jrsoftware.org/ishelp/topic_setupcmdline.htm).
