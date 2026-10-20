import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'lyrics.dart';
import 'data_files.dart';
import 'models.dart';
import 'player.dart';
import 'wave_seek_bar.dart';

const lyricsBackground = Color(0xFF111015);
const lyricsHighlight = Color(0xFFC7B5FF);
const _lyricsSurface = Color(0xFF19171E);
const _lyricsPlay = Color(0xFFC7B5FF);

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.player,
    required this.repository,
    required this.artwork,
    required this.onBack,
    this.loadEmbedded,
    this.files = const DataFiles(),
  });
  final DataFiles files;
  final PlayerController player;
  final LyricsRepository repository;
  final Widget artwork;
  final VoidCallback onBack;
  final Future<Lyrics?> Function(Track)? loadEmbedded;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  Track? _track;
  Lyrics? _lyrics;
  String? _error;
  bool _importing = false;
  bool _loading = false, _synced = true, _looked = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.player.current, _track)) _reset();
  }

  void _reset() {
    _generation++;
    _track = widget.player.current;
    _lyrics = _track == null ? null : widget.repository.cached(_track!);
    _looked = _track != null && widget.repository.contains(_track!);
    _loading = false;
    _error = null;
    _synced = _lyrics == null || _lyrics!.lines.isNotEmpty;
    if (_lyrics == null && widget.loadEmbedded != null) unawaited(_embedded());
  }

  Future<void> _embedded() async {
    final track = _track, load = widget.loadEmbedded;
    if (track == null || load == null || _loading) return;
    final generation = ++_generation;
    _loading = true;
    try {
      final lyrics = await load(track);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (lyrics != null) {
          _lyrics = lyrics;
          widget.repository.save(track, lyrics);
          _synced = lyrics.lines.isNotEmpty;
          _error = null;
        }
      });
    } catch (_) {
      // Missing or unavailable tags leave lookup and paste available.
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _find() async {
    final track = _track;
    if (track == null || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lyrics = await widget.repository.find(track);
      if (!mounted || generation != _generation) return;
      setState(() {
        _lyrics = lyrics;
        _looked = true;
        _synced = lyrics != null && lyrics.lines.isNotEmpty;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = 'Could not load lyrics. Check your connection and try again, or paste lyrics.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _import() async {
    final track = _track;
    if (track == null || _importing) return;
    final generation = _generation;
    setState(() => _importing = true);
    try {
      final path = await widget.files.openLyrics();
      if (path == null || !mounted || generation != _generation) return;
      final bytes = await widget.files.readBytes(
        path,
        maxBytes: Lyrics.maxFileBytes,
      );
      final lyrics = Lyrics.fromFileBytes(bytes);
      if (!mounted || generation != _generation || !identical(track, _track)) {
        return;
      }
      _useLyrics(track, lyrics);
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not import lyrics. Choose a UTF-8 or UTF-16 .lrc file up to 256 KiB with at most 2000 lines.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _paste() async {
    final track = _track;
    if (track == null) return;
    var text = '';
    final lyrics = await showDialog<Lyrics>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Paste lyrics'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Use plain text or LRC with [mm:ss.xx] timestamps. Kept only for this app session.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (value) => text = value,
                      minLines: 4,
                      maxLines: 9,
                      maxLength: 256 * 1024,
                      decoration: InputDecoration(
                        hintText: '[00:12.50] A lyric line',
                        errorText: error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    final result = Lyrics.parse(text);
                    if (result.plain.isEmpty && result.lines.isEmpty) {
                      throw const FormatException('Paste some lyrics first.');
                    }
                    Navigator.pop(context, result);
                  } on FormatException catch (e) {
                    update(() {
                      error = e.message;
                    });
                  }
                },
                child: const Text('Use lyrics'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || !identical(track, _track) || lyrics == null) return;
    _useLyrics(track, lyrics);
  }

  void _useLyrics(Track track, Lyrics lyrics) {
    _generation++;
    widget.repository.save(track, lyrics);
    setState(() {
      _lyrics = lyrics;
      _looked = true;
      _loading = false;
      _error = null;
      _synced = lyrics.lines.isNotEmpty;
    });
  }

  Widget _message(String text) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, height: 1.6),
      ),
    ),
  );

  PopupMenuItem<String> _menuAction({
    required String value,
    required bool enabled,
    required IconData icon,
    required String title,
    required String subtitle,
  }) => PopupMenuItem<String>(
    value: value,
    enabled: enabled,
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: _LyricsMenuEntry(
      icon: icon,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
    ),
  );

  Widget _options({bool vertical = false}) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFF211E28),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: .42),
          elevation: 16,
          menuPadding: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFF312C3B)),
          ),
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Lyrics options',
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 300),
        offset: Offset(vertical ? -6 : 0, vertical ? -10 : 10),
        icon: Icon(
          vertical ? Icons.more_vert_rounded : Icons.more_horiz_rounded,
        ),
        onSelected: (value) {
          if (value == 'import') {
            unawaited(_import());
          } else if (value == 'embedded') {
            setState(() => unawaited(_embedded()));
          } else {
            unawaited(value == 'paste' ? _paste() : _find());
          }
        },
        itemBuilder: (_) => [
          _menuAction(
            value: 'import',
            enabled: _track != null && !_importing,
            icon: Icons.file_open_rounded,
            title: 'Import .lrc file',
            subtitle: 'Use a local synced-lyrics file.',
          ),
          if (widget.loadEmbedded != null)
            _menuAction(
              value: 'embedded',
              enabled: _track != null && !_loading,
              icon: Icons.music_note_rounded,
              title: 'Read lyrics from music file',
              subtitle: 'Try embedded lyrics from this track.',
            ),
          _menuAction(
            value: 'find',
            enabled: _track != null && !_loading,
            icon: Icons.search_rounded,
            title: 'Find lyrics on LRCLIB',
            subtitle: 'Search online using song details.',
          ),
          _menuAction(
            value: 'paste',
            enabled: _track != null,
            icon: Icons.content_paste_rounded,
            title: 'Paste lyrics',
            subtitle: 'Enter plain text or timestamped LRC.',
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final lyrics = _lyrics;
    if (_track == null) return _message('Choose a track to see its lyrics.');
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _message(_error!);
    if (lyrics?.instrumental == true) {
      return _message('Instrumental · no lyrics');
    }
    if (lyrics == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lyrics_rounded,
                size: 44,
                color: lyricsHighlight,
              ),
              const SizedBox(height: 12),
              Text(
                _looked
                    ? 'No lyrics found for this song.'
                    : 'Bring the words into focus.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: const Text(
                  'Embedded lyrics are read from the music file first. Find lyrics sends this song’s title, artist and duration to LRCLIB. Your Telegram account and channel details stay private.',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _find,
                icon: const Icon(Icons.search),
                label: const Text('Find lyrics'),
              ),
              TextButton.icon(
                onPressed: _importing ? null : _import,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('Import .lrc file'),
              ),
              TextButton(
                onPressed: _paste,
                child: const Text('Paste lyrics instead'),
              ),
            ],
          ),
        ),
      );
    }
    if (_synced && lyrics.lines.isNotEmpty) {
      return _SyncedLyrics(
        key: ObjectKey(lyrics),
        lyrics: lyrics,
        player: widget.player,
      );
    }
    return SingleChildScrollView(
      key: ObjectKey(lyrics),
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: SelectableText(
          lyrics.plain,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.7,
          ),
        ),
      ),
    );
  }

  Widget _mode(bool synced) {
    final selected = _synced == synced;
    final label = synced ? 'Synced' : 'Static';
    final icon = synced ? Icons.graphic_eq_rounded : Icons.article_rounded;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          key: ValueKey(synced ? 'lyrics-synced-mode' : 'lyrics-static-mode'),
          style: TextButton.styleFrom(
            backgroundColor: selected
                ? lyricsHighlight
                : const Color(0xFF1D1A23),
            foregroundColor: selected
                ? const Color(0xFF21182F)
                : const Color(0xFFF0EBFF),
            disabledBackgroundColor: const Color(0xFF18161D),
            disabledForegroundColor: const Color(0xFF6C6A76),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: selected
                    ? Colors.transparent
                    : const Color(0xFF302B39),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: synced && _lyrics!.lines.isEmpty
              ? null
              : () => setState(() => _synced = synced),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceText(Lyrics lyrics) => lyrics.online
      ? 'Lyrics: LRCLIB · timings may vary by recording'
      : lyrics.embedded
      ? 'Lyrics from music file'
      : lyrics.imported
      ? 'Imported LRC · session only'
      : 'Pasted lyrics · session only';

  Widget _surfaceCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    double radius = 30,
  }) => Material(
    color: _lyricsSurface,
    elevation: 0,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );

  Widget _headerCard(bool short) {
    final track = _track;
    final lyrics = _lyrics;
    return _surfaceCard(
      padding: const EdgeInsets.all(6),
      radius: 30,
      child: Row(
        key: const ValueKey('lyrics-song-pill'),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(short ? 18 : 22),
            child: SizedBox(
              width: short ? 54 : 62,
              height: short ? 54 : 62,
              child: widget.artwork,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: short ? 18 : 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  track?.artist ?? 'Choose a track first',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFAAA7B4),
                  ),
                ),
                if (lyrics != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: lyricsHighlight.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      lyrics.instrumental
                          ? 'Instrumental'
                          : (_synced && lyrics.lines.isNotEmpty
                                ? 'Following timed lyrics'
                                : 'Showing static lyrics'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: lyricsHighlight,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _options(),
        ],
      ),
    );
  }

  Widget _bodyCard() => _surfaceCard(
    padding: EdgeInsets.zero,
    radius: 32,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: _body(),
    ),
  );

  Widget _playback(bool short, bool reduced) {
    final player = widget.player, audio = player.audio;
    final duration = audio.duration.inMilliseconds;
    final progress = duration <= 0
        ? 0.0
        : (audio.position.inMilliseconds / duration).clamp(0.0, 1.0);
    final buffered = duration <= 0
        ? 0.0
        : (audio.buffered.inMilliseconds / duration).clamp(0.0, 1.0);
    final size = short ? 48.0 : 72.0;
    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: IconButton.filled(
            key: const ValueKey('lyrics-play-pause'),
            tooltip: audio.playing ? 'Pause' : 'Play',
            style:
                IconButton.styleFrom(
                  backgroundColor: _lyricsPlay,
                  foregroundColor: const Color(0xFF21182F),
                  disabledBackgroundColor: _lyricsPlay.withValues(alpha: .35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      audio.playing ? 20 : size / 2,
                    ),
                  ),
                ).copyWith(
                  animationDuration: Duration(milliseconds: reduced ? 0 : 220),
                ),
            onPressed: _track == null || player.loading
                ? null
                : () async {
                    try {
                      await audio.toggle();
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not change playback.'),
                          ),
                        );
                      }
                    }
                  },
            icon: AnimatedSwitcher(
              duration: Duration(milliseconds: reduced ? 0 : 180),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: player.loading || audio.buffering
                  ? const SizedBox(
                      key: ValueKey('lyrics-buffering'),
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      audio.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      key: ValueKey(audio.playing),
                      size: short ? 28 : 36,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DecoratedBox(
            key: const ValueKey('lyrics-seek-pill'),
            decoration: BoxDecoration(
              color: _lyricsSurface,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: WaveSeekBar(
                value: progress,
                buffered: buffered,
                playing: audio.playing && !audio.buffering && _track != null,
                reducedMotion: reduced,
                format: (value) => clockText(
                  Duration(milliseconds: (value * duration).round()),
                ),
                onChanged: duration <= 0
                    ? null
                    : (value) async {
                        try {
                          await player.seek(
                            Duration(milliseconds: (value * duration).round()),
                          );
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not seek to this position.',
                                ),
                              ),
                            );
                          }
                        }
                      },
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _transportDock({
    required bool short,
    required bool reduced,
    required bool showModeSelector,
  }) => _surfaceCard(
    radius: 32,
    padding: EdgeInsets.fromLTRB(16, short ? 14 : 16, 16, short ? 14 : 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _playback(short, reduced),
        if (showModeSelector) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              _mode(true),
              const SizedBox(width: 10),
              _mode(false),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _footerMetaRow({required bool compact}) {
    final lyrics = _lyrics;
    final source = lyrics == null
        ? 'Lyrics source will appear here'
        : _sourceText(lyrics);
    return Row(
      children: [
        IconButton.filled(
          onPressed: widget.onBack,
          tooltip: 'Back to cover',
          style: IconButton.styleFrom(
            backgroundColor: _lyricsSurface,
            foregroundColor: const Color(0xFFE4E0EF),
          ),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            source,
            textAlign: compact ? TextAlign.center : TextAlign.left,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFFAAA4B5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: _lyricsSurface,
          shape: const CircleBorder(),
          child: _options(vertical: true),
        ),
      ],
    );
  }

  Widget _infoPanel(bool short) {
    final track = _track;
    final lyrics = _lyrics;
    return Column(
      children: [
        _surfaceCard(
          radius: 32,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF14121A),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: widget.artwork,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                track?.title ?? 'Nothing playing',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: short ? 20 : 22,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                track?.artist ?? 'Choose a track first',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFB0ABBA),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF15131A),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF2B2733)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lyrics source',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9D97AC),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lyrics == null ? 'No lyrics loaded yet.' : _sourceText(lyrics),
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFFE7E2F3),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (lyrics != null && !lyrics.instrumental)
          _surfaceCard(
            radius: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reading mode',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9D97AC),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _mode(true),
                    const SizedBox(width: 10),
                    _mode(false),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _compactLayout({required bool short, required bool reduced}) {
    final lyrics = _lyrics;
    final showModeSelector = lyrics != null && !lyrics.instrumental;
    return Column(
      children: [
        _headerCard(short),
        const SizedBox(height: 12),
        Expanded(child: _bodyCard()),
        const SizedBox(height: 12),
        _transportDock(
          short: short,
          reduced: reduced,
          showModeSelector: showModeSelector,
        ),
        const SizedBox(height: 10),
        _footerMetaRow(compact: true),
      ],
    );
  }

  Widget _wideLayout({required bool short, required bool reduced}) => Column(
    children: [
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  _headerCard(short),
                  const SizedBox(height: 14),
                  Expanded(child: _bodyCard()),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 320,
              child: _infoPanel(short),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _transportDock(short: short, reduced: reduced, showModeSelector: false),
      const SizedBox(height: 10),
      _footerMetaRow(compact: false),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final reduced =
        widget.player.settings.reducedMotion ||
        MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: lyricsHighlight,
          onPrimary: const Color(0xFF21182F),
          surface: _lyricsSurface,
          onSurface: const Color(0xFFE4E0EF),
        ),
      ),
      child: Material(
        key: const ValueKey('lyrics-immersive'),
        color: lyricsBackground,
        child: LayoutBuilder(
          builder: (context, box) {
            final short = box.maxHeight < 420;
            final wide = box.maxWidth >= 1000 && box.maxHeight >= 560;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, short ? 8 : 16, 16, short ? 8 : 14),
              child: wide
                  ? _wideLayout(short: short, reduced: reduced)
                  : _compactLayout(short: short, reduced: reduced),
            );
          },
        ),
      ),
    );
  }

}


class _LyricsMenuEntry extends StatelessWidget {
  const _LyricsMenuEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? const Color(0xFFF0EBFF)
        : const Color(0xFF7B748A);
    final secondary = enabled
        ? const Color(0xFFB8B1C8)
        : const Color(0xFF676170);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: enabled
                  ? lyricsHighlight.withValues(alpha: .14)
                  : Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: foreground, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncedLyrics extends StatefulWidget {
  const _SyncedLyrics({super.key, required this.lyrics, required this.player});
  final Lyrics lyrics;
  final PlayerController player;
  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
  final _scroll = ScrollController();
  bool _follow = true;
  int? _lastActive;
  double? _width, _height;
  TextScaler? _scaler;
  TextStyle? _style;
  TextDirection? _direction;
  final _heights = <double>[], _offsets = <double>[];
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final active = widget.lyrics.activeAt(widget.player.audio.position);
      final scaler = MediaQuery.textScalerOf(context);
      final reduced =
          widget.player.settings.reducedMotion ||
          MediaQuery.disableAnimationsOf(context);
      final direction = Directionality.of(context);
      final style = TextStyle(
        fontSize: box.maxWidth < 500 ? 23 : 32,
        height: 1.35,
        fontWeight: FontWeight.w700,
        fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
      );
      final changed =
          _width != box.maxWidth ||
          _scaler != scaler ||
          _height != box.maxHeight ||
          _style != style ||
          _direction != direction;
      if (changed) {
        _width = box.maxWidth;
        _height = box.maxHeight;
        _scaler = scaler;
        _style = style;
        _direction = direction;
        _heights.clear();
        _offsets.clear();
        var offset = 0.0;
        for (final line in widget.lyrics.lines) {
          final painter = TextPainter(
            text: TextSpan(
              text: line.text.isEmpty ? '♪' : line.text,
              style: style,
            ),
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: math.max(1, box.maxWidth - 48));
          final height = math.max(76.0, painter.height + 44);
          painter.dispose();
          _offsets.add(offset);
          _heights.add(height);
          offset += height;
        }
      }
      if (_follow && (_lastActive != active || changed)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_follow || !_scroll.hasClients) return;
          final target =
              (active < 0 ? 0.0 : _offsets[active] + _heights[active] / 2)
                  .clamp(0.0, _scroll.position.maxScrollExtent);
          if (reduced) {
            _scroll.jumpTo(target);
          } else {
            unawaited(
              _scroll.animateTo(
                target,
                duration: const Duration(milliseconds: 480),
                curve: Curves.easeOutCubic,
              ),
            );
          }
        });
      }
      _lastActive = active;
      return Stack(
        children: [
          NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.direction != ScrollDirection.idle && _follow) {
                setState(() {
                  _follow = false;
                });
              }
              return false;
            },
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0, .12, .86, 1],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: ListView.builder(
                key: const ValueKey('synced-lyrics'),
                controller: _scroll,
                padding: EdgeInsets.symmetric(vertical: box.maxHeight * .5),
                itemCount: widget.lyrics.lines.length,
                itemExtentBuilder: (index, _) => _heights[index],
                itemBuilder: (context, index) {
                  final line = widget.lyrics.lines[index];
                  final current = active == index;
                  final distance = (index - active).abs();
                  return Semantics(
                    selected: current,
                    button: true,
                    label: 'Seek to ${clockText(line.time)}',
                    child: InkWell(
                      key: ValueKey('lyric-$index'),
                      onTap: () async {
                        try {
                          final duration = widget.player.audio.duration;
                          final target =
                              duration > Duration.zero && line.time > duration
                              ? duration
                              : line.time;
                          await widget.player.seek(target);
                          if (mounted) {
                            setState(() {
                              _follow = true;
                              _lastActive = null;
                            });
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not seek to this lyric.'),
                              ),
                            );
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 22,
                        ),
                        child: TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: reduced ? 0 : 360),
                          curve: Curves.easeOutCubic,
                          tween: Tween(
                            end: current || !_follow
                                ? 0.0
                                : math.min(3.0, 1.5 + distance * .35),
                          ),
                          builder: (context, blur, child) => ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: blur,
                              sigmaY: blur,
                            ),
                            enabled: blur > .01,
                            child: child,
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: Duration(milliseconds: reduced ? 0 : 360),
                            curve: Curves.easeOutCubic,
                            style: style.copyWith(
                              color: current
                                  ? lyricsHighlight
                                  : Colors.white.withValues(
                                      alpha: !_follow
                                          ? .72
                                          : (distance <= 1 ? .24 : .12),
                                    ),
                            ),
                            child: Text(line.text.isEmpty ? '♪' : line.text),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (!_follow)
            Positioned(
              bottom: 6,
              right: 12,
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() {
                  _follow = true;
                  _lastActive = null;
                }),
                icon: const Icon(Icons.my_location_rounded, size: 16),
                label: const Text('Follow song'),
              ),
            ),
        ],
      );
    },
  );
}
