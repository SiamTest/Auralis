# GitHub Releases and application updates

Configured repository: **[SiamTest/Auralis](https://github.com/SiamTest/Auralis)**. [Run 39264104723](https://github.com/SiamTest/Auralis/actions/runs/39264104723) passed the app build, native smoke tests and installer packaging for `v0.1.3`, and reused/saved the TDLib cache without compiling it. Publishing created/uploaded to a draft, then failed with HTTP 404 because its digest check used the published-only by-tag endpoint. This revision adds embedded-cover extraction and saved Library sorting, retains the repair for draft lookup using its numeric release ID and targets `v0.1.5`, preserving the already-created `v0.1.3` tag. The current connection has **READ** permission, so this task has not pushed or published the change. Commit this revision to run the updated workflow; rerunning an old commit does not apply it.

## Release flow

1. Upload the complete project as the repository root, including `.github`, `pubspec.lock`, tests, native notices and the vendored runtime. A push to `main` runs the Windows build/test/package job and, after success, the stable publisher. A manual run on `main` does the same. Other branches and pull requests produce artifacts only.
2. Analysis, automated tests, native smoke tests and installer packaging must succeed. The job packages a portable ZIP, per-user Inno Setup installer, application source ZIP from the committed revision, and `SHA256SUMS.txt`.
3. The publisher reads the stable version from `pubspec.yaml`. For the current `0.1.5+6`, it creates `v0.1.5` at the exact tested commit if that tag is absent. No manual tag is required. An existing tag must already resolve to the tested commit; it is never moved. Explicit stable tag builds remain supported and must match `pubspec.yaml`.
4. Using the publishing job's `GITHUB_TOKEN` with `contents: write`, it creates an unpublished draft with `--prerelease=false`. It resolves the draft-aware CLI lookup's numeric `databaseId`, checks that the corresponding REST release has the intended tag and remains a non-prerelease draft, then uploads all four assets. It refreshes metadata by numeric ID, verifies GitHub's SHA-256 asset digests, then publishes with `--draft=false --prerelease=false`. It never uses the published-only by-tag REST route to verify a draft. The newest stable version is marked Latest; releasing an older version preserves a newer Latest. Build permissions remain read-only, and publishing jobs serialize to avoid concurrent tag/asset updates.
5. Published versions are immutable. A later push with the same version reports that it is already stable and skips release mutation. For the next app update, bump `pubspec.yaml` to a new stable version, such as `0.1.6+7`, and commit to `main`; it automatically publishes `v0.1.6` after successful checks. A build-number-only change does not create a new stable release. An existing published prerelease is not silently overwritten; use a new stable version.

Optional tag-based release after completing the native distribution audit:

```powershell
git tag v0.1.5
git push origin v0.1.5
```

Tags such as `v0.1.3-beta`, mismatched versions, pull requests, other branches and mismatched checkout commits cannot publish. Existing drafts may resume only at their original tested tag/commit; a failed digest check leaves the draft unpublished. GitHub API permission/network errors fail explicitly instead of being treated as a missing release. An `untagged-…` URL is normal for an unpublished draft; it is not a reason to delete or move the version tag. The failed `v0.1.3` draft may remain; the new source uses `v0.1.5` because the existing version tag points to the previous tested commit.

Expected assets for `v0.1.5`:

```text
auralis-0.1.5-windows-x64.zip
auralis-0.1.5-windows-x64-setup.exe
auralis-0.1.5-source.zip
SHA256SUMS.txt
```

GitHub Actions and repository/org policies must permit the publish job's write token. No Telegram credentials or personal access token need to be committed or added to the app. **Windows compilation, native smoke tests and installer compilation passed in run 39232305284. Actual stable publication, installation and in-app update execution remain unverified.** The local machine still lacks Visual Studio C++ Build Tools and Inno Setup. Publisher behavior is tested with a process-local fake GitHub CLI; it makes no external mutations during tests.

## TDLib build cache

The workflow restores `native/*.dll`, `native/licenses/` and `native/build-manifest.json`. The stable v2 key includes Windows 2022/x64/Release, the runner image version and `hashFiles('tool/build-tdlib.ps1')`. That script contains the TDLib/vcpkg pins and native compiler configuration. Changing those native inputs or the runner image invalidates the cache; edits to UI, app version or release/publishing steps do not. Native options belong in the native build script; bump the cache namespace when changing assumptions outside that script.

The earlier v1 key also hashed the entire workflow. [Run 39261767369](https://github.com/SiamTest/Auralis/actions/runs/39261767369) at `a7248a6e308049bee23198f94fdf2545fe50bac6` rebuilt TDLib even though a 12,851,116-byte v1 cache existed. Comparing that revision with successful run `39232305284` confirmed an identical native builder and workflow differences only in the publisher. The release edit changed the combined workflow/builder hash, explaining the miss. A green Restore step means the action completed; it does not by itself establish a hit.

To avoid another full build just to rename the key, the migration step recognizes two audited v1 keys: `dd3ad69f…` from the previously successful build and `5e62127e…` from the running release-workflow revision. Migration is enabled only when the current Windows builder's `hashFiles` is exactly `3bd38120fd24502f920e57bbec0cad701d81e9e660707d0fe01a37997fcc506a`. Both old combined hashes were reproduced from the exact repository files with Windows checkout line endings, and both native builders match. Every key includes the current runner image. A changed builder disables migration.

The previous-cache restore first requests the exact `5e62127e…` key, then the full `dd3ad69f…` key as a fallback. Only an exact recognized key may skip compilation; an unexpected prefix extension is rejected by the build condition. A stable-key hit skips native compilation and saving. A recognized legacy hit skips compilation and saves the payload under the stable key. If all acceptable entries miss, the pinned source build runs and is saved immediately afterward. The source, payload paths and archive-version inputs are preserved. Native smoke tests still run for every path.

GitHub controls cache scope, quotas and eviction, so a missing cache or changed image can still cause compilation; no fixed timing is promised. The migration is a compatibility bridge and can be removed after the relevant images have stable-key caches. To force a fresh cache, change the `tdlib-...-v2` namespace and remove/disable legacy migration for that change. The cached payload contains build outputs and notices only, with no credentials, sessions or downloaded music.

The currently running job cannot adopt a new workflow midway through; let it finish before committing the update if you want to preserve its work. This task cannot upload the fix through the READ-only connection. The complete project ZIP includes it; replacing only `.github/workflows/windows.yml` also applies this configuration fix. Actual GitHub migration/hit behavior still needs a new run.

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
