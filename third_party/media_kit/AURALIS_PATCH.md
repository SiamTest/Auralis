# Windows shutdown patch

Vendored Dart runtime source of media_kit 1.2.6 from the pub.dev package archive, under its original MIT license (see LICENSE). Copyright headers are retained. Publisher screenshots and the optional web HLS asset are omitted for this Windows application. This is third-party code, distinct from Auralis's AGPL application code. No mpvRx or PixelPlayer code is involved.

Changes by Auralis contributors, 19 October 2026:

- Windows `NativePlayer.dispose()` awaits native termination instead of returning and scheduling `mpv_terminate_destroy` five seconds later.
- Unregister the wakeup callback, stop Dart event polling, drain its per-handle event lock, terminate/join the native player in a worker isolate, and only then close the `NativeCallable`.
- Event callbacks queued before disposal return without polling a removed native handle.
- Other platforms retain the upstream disposal path. This app targets Windows x64 only.

The fix applies to both the desktop app and standalone smoke tests via a path dependency. Do not substitute a changed global pub cache or suppress the smoke process's exit code. When upgrading media_kit, compare this patch against the upstream shutdown implementation and rerun native shutdown tests.

Upstream: https://pub.dev/packages/media_kit/versions/1.2.6 and https://github.com/media-kit/media-kit. See also upstream issue https://github.com/media-kit/media-kit/issues/1443 for the callback-lifetime ordering problem (reported on Android; the local patch here is Windows-specific).
