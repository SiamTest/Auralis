import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'lyrics.dart';
import 'models.dart';
import 'player.dart';
import 'wave_seek_bar.dart';

const lyricsBackground = Color(0xFF004E64);
const lyricsHighlight = Color(0xFF68D3F5);
const _lyricsSurface = Color(0xFF0D0E17);
const _lyricsPlay = Color(0xFFC5BEFF);

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.player,
    required this.repository,
    required this.artwork,
    required this.onBack,
  });
  final PlayerController player;
  final LyricsRepository repository;
  final Widget artwork;
  final VoidCallback onBack;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  Track? _track;
  Lyrics? _lyrics;
  String? _error;
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

  Widget _options({bool vertical = false}) => PopupMenuButton<String>(
    tooltip: 'Lyrics options',
    icon: Icon(vertical ? Icons.more_vert_rounded : Icons.more_horiz_rounded),
    onSelected: (value) {
      unawaited(value == 'paste' ? _paste() : _find());
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'find',
        enabled: _track != null && !_loading,
        child: const Text('Find lyrics on LRCLIB'),
      ),
      PopupMenuItem(
        value: 'paste',
        enabled: _track != null,
        child: const Text('Paste lyrics'),
      ),
    ],
  );

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
                  'Find lyrics sends this song’s title, artist and duration to LRCLIB. Your Telegram account and channel details stay private.',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _find,
                icon: const Icon(Icons.search),
                label: const Text('Find lyrics'),
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
    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          key: ValueKey(synced ? 'lyrics-synced-mode' : 'lyrics-static-mode'),
          style: TextButton.styleFrom(
            backgroundColor: selected ? lyricsHighlight : _lyricsSurface,
            foregroundColor: selected
                ? const Color(0xFF003447)
                : const Color(0xFFE4E0EF),
            disabledBackgroundColor: _lyricsSurface,
            disabledForegroundColor: const Color(0xFF6C6A76),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(selected ? 40 : 12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            textStyle: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          onPressed: synced && _lyrics!.lines.isEmpty
              ? null
              : () => setState(() => _synced = synced),
          child: Text(synced ? 'Synced' : 'Static'),
        ),
      ),
    );
  }

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
                  foregroundColor: const Color(0xFF16174D),
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

  @override
  Widget build(BuildContext context) {
    final track = _track, lyrics = _lyrics;
    final reduced =
        widget.player.settings.reducedMotion ||
        MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: lyricsHighlight,
          onPrimary: const Color(0xFF003447),
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
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, short ? 6 : 16, 16, 4),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Material(
                        key: const ValueKey('lyrics-song-pill'),
                        color: _lyricsSurface,
                        borderRadius: BorderRadius.circular(48),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Row(
                            children: [
                              ClipOval(
                                child: SizedBox(
                                  width: short ? 40 : 50,
                                  height: short ? 40 : 50,
                                  child: widget.artwork,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      track?.title ?? 'Nothing playing',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      track?.artist ?? 'Choose a track first',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFFAAA7B4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _options(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: _body()),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, short ? 6 : 14),
                  child: _playback(short, reduced),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: lyrics != null && !lyrics.instrumental
                            ? Row(
                                children: [
                                  _mode(true),
                                  const SizedBox(width: 8),
                                  _mode(false),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: _lyricsSurface,
                        shape: const CircleBorder(),
                        child: _options(vertical: true),
                      ),
                    ],
                  ),
                ),
                if (lyrics != null && !short)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      lyrics.online
                          ? 'Lyrics: LRCLIB · timings may vary by recording'
                          : 'Pasted lyrics · session only',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFA0BBC4),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
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
