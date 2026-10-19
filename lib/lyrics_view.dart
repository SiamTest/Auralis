import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'lyrics.dart';
import 'models.dart';
import 'player.dart';

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

  @override
  Widget build(BuildContext context) {
    final track = _track, lyrics = _lyrics;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: .15), const Color(0xFF15121D)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  tooltip: 'Back to cover',
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                SizedBox(width: 40, height: 40, child: widget.artwork),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? 'Nothing playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        track?.artist ?? 'Choose a track first',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Lyrics options',
                  onSelected: (value) {
                    if (value == 'paste') {
                      unawaited(_paste());
                    } else {
                      unawaited(_find());
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'find',
                      enabled: track != null && !_loading,
                      child: const Text('Find lyrics on LRCLIB'),
                    ),
                    PopupMenuItem(
                      value: 'paste',
                      enabled: track != null,
                      child: const Text('Paste lyrics'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: track == null
                ? _message('Choose a track to see its lyrics.')
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _message(_error!)
                : lyrics?.instrumental == true
                ? _message('Instrumental · no lyrics')
                : lyrics == null
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.lyrics_rounded, size: 44, color: accent),
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
                        const Text(
                          'Find lyrics sends this song’s title, artist and duration to LRCLIB. Your Telegram account and channel details stay private.',
                          textAlign: TextAlign.center,
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
                  )
                : _synced && lyrics.lines.isNotEmpty
                ? _SyncedLyrics(
                    key: ObjectKey(lyrics),
                    lyrics: lyrics,
                    player: widget.player,
                  )
                : SingleChildScrollView(
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
                  ),
          ),
          if (lyrics != null && !lyrics.instrumental)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: const Text('Synced'),
                        enabled: lyrics.lines.isNotEmpty,
                      ),
                      const ButtonSegment(value: false, label: Text('Static')),
                    ],
                    selected: {_synced},
                    onSelectionChanged: (value) => setState(() {
                      _synced = value.single;
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lyrics.online
                        ? 'Lyrics: LRCLIB · timings may vary by recording'
                        : 'Pasted lyrics · session only',
                    style: const TextStyle(fontSize: 10),
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
      final style = TextStyle(
        fontSize: box.maxWidth < 500 ? 23 : 32,
        height: 1.5,
        fontWeight: FontWeight.w700,
        fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
      );
      final changed =
          _width != box.maxWidth ||
          _scaler != scaler ||
          _height != box.maxHeight;
      if (changed) {
        _width = box.maxWidth;
        _height = box.maxHeight;
        _scaler = scaler;
        _heights.clear();
        _offsets.clear();
        var offset = 0.0;
        for (final line in widget.lyrics.lines) {
          final painter = TextPainter(
            text: TextSpan(
              text: line.text.isEmpty ? '♪' : line.text,
              style: style,
            ),
            textDirection: Directionality.of(context),
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
          if (widget.player.settings.reducedMotion ||
              MediaQuery.disableAnimationsOf(context)) {
            _scroll.jumpTo(target);
          } else {
            unawaited(
              _scroll.animateTo(
                target,
                duration: const Duration(milliseconds: 350),
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
                        await widget.player.audio.seek(target);
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
                      child: Text(
                        line.text.isEmpty ? '♪' : line.text,
                        style: style.copyWith(
                          color: current
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withValues(
                                  alpha: distance <= 1 ? .48 : .23,
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
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
