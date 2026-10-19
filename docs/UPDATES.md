# GitHub Releases and application updates

Configured repository: **[SiamTest/Auralis](https://github.com/SiamTest/Auralis)**. [Run 39232305284](https://github.com/SiamTest/Auralis/actions/runs/39232305284) passed the app build, native smoke tests and installer packaging, and saved the TDLib cache. It did not release because the previous workflow published only version tags. This revision adds automatic stable publication from `main`. The current connection has **READ** permission, so this task has not pushed or published the change. Commit this revision to run the updated workflow; rerunning an old commit does not apply it.

## Release flow

1. Upload the complete project as the repository root, including `.github`, `pubspec.lock`, tests, native notices and the vendored runtime. A push to `main` runs the Windows build/test/package job and, after success, the stable publisher. A manual run on `main` does the same. Other branches and pull requests produce artifacts only.
2. Analysis, automated tests, native smoke tests and installer packaging must succeed. The job packages a portable ZIP, per-user Inno Setup installer, application source ZIP from the committed revision, and `SHA256SUMS.txt`.
3. The publisher reads the stable version from `pubspec.yaml`. For the current `0.1.3+4`, it creates `v0.1.3` at the exact tested commit if that tag is absent. No manual tag is required. An existing tag must already resolve to the tested commit; it is never moved. Explicit stable tag builds remain supported and must match `pubspec.yaml`.
4. Using the publishing job's `GITHUB_TOKEN` with `contents: write`, it creates an unpublished draft with `--prerelease=false`, uploads all four assets, verifies GitHub's SHA-256 digests, then publishes with `--draft=false --prerelease=false`. The newest stable version is marked Latest; releasing an older version preserves a newer Latest. Build permissions remain read-only, and publishing jobs serialize to avoid concurrent tag/asset updates.
5. Published versions are immutable. A later push with the same version reports that it is already stable and skips release mutation. For the next app update, bump `pubspec.yaml` to a new stable version, such as `0.1.4+5`, and commit to `main`; it automatically publishes `v0.1.4` after successful checks. A build-number-only change does not create a new stable release. An existing published prerelease is not silently overwritten; use a new stable version.

Optional tag-based release after completing the native distribution audit:

```powershell
git tag v0.1.3
git push origin v0.1.3
```

Tags such as `v0.1.3-beta`, mismatched versions, pull requests, other branches and mismatched checkout commits cannot publish. Existing drafts may resume only at their original tested tag/commit; a failed digest check leaves the draft unpublished. GitHub API permission/network errors fail explicitly instead of being treated as a missing release.

Expected assets for `v0.1.3`:

```text
auralis-0.1.3-windows-x64.zip
auralis-0.1.3-windows-x64-setup.exe
auralis-0.1.3-source.zip
SHA256SUMS.txt
```

GitHub Actions and repository/org policies must permit the publish job's write token. No Telegram credentials or personal access token need to be committed or added to the app. **Windows compilation, native smoke tests and installer compilation passed in run 39232305284. Actual stable publication, installation and in-app update execution remain unverified.** The local machine still lacks Visual Studio C++ Build Tools and Inno Setup. Publisher behavior is tested with a process-local fake GitHub CLI; it makes no external mutations during tests.

## TDLib build cache

The workflow restores an exact cache of `native/*.dll`, `native/licenses/` and `native/build-manifest.json`, then skips `tool/build-tdlib.ps1` only when `cache-hit` is `true`. A cache miss runs the same pinned source build. The cache is saved immediately after that build succeeds, before the Flutter build, native smoke test or packaging: a later failure therefore does not discard the expensive TDLib build.

The key includes Windows 2022/x64/Release, GitHub's runner image version, and the hashes of `tool/build-tdlib.ps1` and `.github/workflows/windows.yml`. It changes when pinned TDLib/vcpkg revisions, build options, the workflow or the Windows image change. There are no prefix fallback keys that could restore incompatible binaries. The cache contains build outputs and notices only, with no Telegram account credentials, databases or downloaded music. Native smoke checks still run on cache hits.

The first run with this workflow needs to build and save the cache. Existing runs cannot adopt the change midway through, and old runs did not save a TDLib cache. GitHub controls cache scope, quotas and eviction, so a missing/expired cache causes another full build; no fixed speedup is promised. Ordinary app-source changes can reuse a matching cache. To force a rebuild, delete the matching entry under Actions caches or change the `tdlib-...-v1` key prefix.

The cache was successfully saved by run 39232305284. This stable-publishing workflow edit changes the hashed workflow input, so its first run requires another native build; later identical keys can reuse that cache.

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

The original native playback corresponding-source/security audit remains outstanding. **Resolve native source/licenses and codec updates before public binary distribution.** This revision publishes automatically from successful `main` builds as requested; technical checks and a stable-release flag do not substitute for that audit. The application source ZIP contains this project, not complete corresponding source for every prebuilt native playback dependency. See `THIRD_PARTY_NOTICES.md`.

Primary documentation: [GitHub release API](https://docs.github.com/en/rest/releases/releases), [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create), [Inno Setup command-line parameters](https://jrsoftware.org/ishelp/topic_setupcmdline.htm).
