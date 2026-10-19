import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'player.dart';
import 'telegram/telegram_service.dart';
import 'updater.dart';
import 'update_widgets.dart';

const accent = Color(0xFFC7B5FF),
    surface = Color(0xFF19171E),
    muted = Color(0xFFAAA4B5);

class AuralisApp extends StatelessWidget {
  const AuralisApp({
    super.key,
    required this.player,
    required this.telegram,
    this.startupWarning,
    this.updater,
  });
  final PlayerController player;
  final TelegramService telegram;
  final String? startupWarning;
  final AppUpdater? updater;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Auralis',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: const Color(0xFF111015),
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
        primary: accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF211E28),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      dividerColor: const Color(0xFF302B39),
    ),
    home: PlayerShell(
      player: player,
      telegram: telegram,
      startupWarning: startupWarning,
      updater: updater,
    ),
  );
}

class PlayerShell extends StatefulWidget {
  const PlayerShell({
    super.key,
    required this.player,
    required this.telegram,
    this.startupWarning,
    this.updater,
  });
  final PlayerController player;
  final TelegramService telegram;
  final String? startupWarning;
  final AppUpdater? updater;
  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  int destination = 0, cursor = 0, _browseGeneration = 0;
  final search = TextEditingController();
  List<Track> local = [], telegramTracks = [];
  MusicChat? chat;
  bool loading = false, documents = false;
  String? browseError;
  PlayerController get player => widget.player;
  TelegramService get telegram => widget.telegram;
  @override
  void initState() {
    super.initState();
    local = player.settings.localFiles.map(Track.local).toList();
    search.addListener(_changed);
    telegram.addListener(_telegramChanged);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _telegramChanged() {
    if (!telegram.ready && (chat != null || telegramTracks.isNotEmpty)) {
      ++_browseGeneration;
      chat = null;
      telegramTracks = [];
      loading = false;
    }
    _changed();
  }

  @override
  void dispose() {
    telegram.removeListener(_telegramChanged);
    search.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Audio', extensions: audioExtensions),
        ],
      );
      if (!mounted || files.isEmpty) return;
      final paths = {
        ...player.settings.localFiles,
        ...files.map((f) => f.path),
      }.toList();
      player.settings.localFiles = paths;
      await player.settings.save();
      if (mounted) {
        setState(() {
          local = paths.map(Track.local).toList();
          destination = 0;
        });
      }
    } catch (_) {
      _notice('Could not import audio. Check file access and try again.');
    }
  }

  void _notice(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _browse(MusicChat selected, {bool more = false}) async {
    final generation = ++_browseGeneration;
    setState(() {
      chat = selected;
      loading = true;
      browseError = null;
      if (!more) {
        telegramTracks = [];
        cursor = 0;
      }
    });
    try {
      final result = await telegram.music(
        selected.id,
        selected.title,
        before: more ? cursor : 0,
        documents: documents,
      );
      if (!mounted || generation != _browseGeneration) return;
      setState(() {
        final ids = telegramTracks.map((t) => t.id).toSet();
        telegramTracks.addAll(result.where((t) => ids.add(t.id)));
        cursor = telegram.nextMessageId;
      });
    } catch (_) {
      if (mounted && generation == _browseGeneration) {
        setState(() {
          browseError = 'Could not load this chat. Check access and connection, then retry.';
        });
      }
    } finally {
      if (mounted && generation == _browseGeneration) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([player, telegram]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 760, wide = box.maxWidth >= 1220;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
                unawaited(_import()),
            const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
                unawaited(player.audio.toggle()),
            const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
                unawaited(player.next()),
            const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () =>
                unawaited(player.previous()),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _navigation(narrow),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                narrow ? 16 : 30,
                                26,
                                narrow ? 16 : 26,
                                0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _header(narrow),
                                  const SizedBox(height: 22),
                                  if (widget.updater != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: UpdateBanner(
                                        updater: widget.updater!,
                                      ),
                                    ),
                                  if (widget.startupWarning != null)
                                    _banner(widget.startupWarning!),
                                  if (player.error ?? player.audio.error
                                      case final String error)
                                    _banner(error),
                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration: Duration(
                                        milliseconds:
                                            player.settings.reducedMotion ||
                                                MediaQuery.disableAnimationsOf(
                                                  context,
                                                )
                                            ? 0
                                            : 180,
                                      ),
                                      child: KeyedSubtree(
                                        key: ValueKey(destination),
                                        child: switch (destination) {
                                          0 => _library(),
                                          1 => _telegram(),
                                          2 => _queue(),
                                          _ => _nowPlaying(),
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (wide && destination != 3)
                            Container(
                              width: 300,
                              margin: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: _nowPlaying(compact: true),
                            ),
                        ],
                      ),
                    ),
                    _transport(narrow),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _navigation(bool narrow) => Container(
    width: narrow ? 72 : 202,
    decoration: const BoxDecoration(
      color: Color(0xFF17151B),
      border: Border(right: BorderSide(color: Color(0xFF26222E))),
    ),
    padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 14, vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.graphic_eq_rounded, color: accent, size: 30),
            if (!narrow) ...[
              const SizedBox(width: 10),
              const Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'auralis',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.3,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (!narrow)
          const Text(
            'A LITTLE CLOSER TO MUSIC',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 8, letterSpacing: 1.4),
          ),
        SizedBox(height: narrow ? 20 : 32),
        for (final (i, icon, label) in [
          (0, Icons.library_music_rounded, 'Library'),
          (1, Icons.send_rounded, 'Telegram'),
          (2, Icons.queue_music_rounded, 'Play queue'),
          (3, Icons.album_rounded, 'Now playing'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Tooltip(
              message: label,
              child: Material(
                color: destination == i
                    ? const Color(0xFF332B45)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() {
                    destination = i;
                    search.clear();
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: narrow
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        Icon(
                          icon,
                          color: destination == i ? accent : muted,
                          size: 23,
                        ),
                        if (!narrow) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: destination == i ? accent : muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        if (!narrow)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'YOUR MUSIC. YOUR SPACE.\n\nIndependent. Open source.',
              style: TextStyle(color: muted, fontSize: 10, height: 1.4),
            ),
          ),
        IconButton(
          onPressed: _settings,
          tooltip: 'Settings',
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    ),
  );

  Widget _header(bool narrow) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'YOUR COLLECTION',
                'MUSIC IN YOUR CHATS',
                'KEEP THE GOOD ONES GOING',
                'IN THE MOMENT',
              ][destination],
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1.7,
                color: accent,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              ['Library', 'Telegram', 'Play queue', 'Now playing'][destination],
              style: TextStyle(
                fontSize: narrow ? 28 : 36,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.4,
              ),
            ),
          ],
        ),
      ),
      if (destination == 0)
        narrow
            ? IconButton(
                onPressed: _import,
                tooltip: 'Add music',
                icon: const Icon(Icons.add_rounded),
              )
            : FilledButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Add music'),
              ),
    ],
  );
  Widget _banner(String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF3C2730),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFFFFCDD8), fontSize: 12),
    ),
  );
  Widget _search(String hint) => TextField(
    controller: search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded, size: 20),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      suffixIcon: search.text.isEmpty
          ? null
          : IconButton(
              onPressed: search.clear,
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
    ),
  );

  Widget _library() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _search('Search your music'),
      const SizedBox(height: 22),
      Wrap(
        spacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.music_note_rounded, size: 17),
            label: Text('${local.length} tracks'),
          ),
          const Chip(label: Text('On this device')),
        ],
      ),
      const SizedBox(height: 12),
      Expanded(
        child: local.isEmpty
            ? _empty(
                Icons.library_music_rounded,
                'Make room for your music',
                'Add a few favorite tracks, or connect Telegram.\nEverything starts with something you love.',
                action: FilledButton.tonalIcon(
                  onPressed: _import,
                  icon: const Icon(Icons.add),
                  label: const Text('Choose audio files'),
                ),
              )
            : _trackList(local),
      ),
    ],
  );
  Widget _trackList(List<Track> tracks) {
    final query = search.text.toLowerCase();
    final visible = tracks
        .where((t) => '${t.title} ${t.artist}'.toLowerCase().contains(query))
        .toList();
    if (visible.isEmpty) {
      return _empty(
        Icons.search_off_rounded,
        'No tracks found',
        'Try another search or choose a different source.',
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, i) => _trackTile(
        visible[i],
        onPlay: () => player.play(visible[i], from: visible),
      ),
    );
  }

  Widget _trackTile(
    Track track, {
    required VoidCallback onPlay,
    bool queued = false,
  }) {
    final active = player.current?.id == track.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? const Color(0xFF2B2438) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onTap: onPlay,
          leading: SizedBox(
            width: 42,
            height: 42,
            child: Artwork(seed: track.title, small: true),
          ),
          title: Text(
            track.title.isEmpty ? 'Untitled audio' : track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? accent : null,
            ),
          ),
          subtitle: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track.duration > Duration.zero)
                Text(
                  clockText(track.duration),
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              if (queued)
                const SizedBox(
                  width: 30,
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 19,
                    color: muted,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Add ${track.title} to queue',
                  onPressed: () {
                    player.enqueue(track);
                    _notice('Added to queue');
                  },
                  icon: const Icon(Icons.playlist_add_rounded, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _telegram() {
    if (!telegram.ready) return _signIn();
    if (chat == null) {
      final chats = telegram.chats
          .where(
            (c) => c.title.toLowerCase().contains(search.text.toLowerCase()),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _search('Find an accessible channel or chat'),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${chats.length} chats · ${telegram.connection}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ),
              TextButton.icon(
                onPressed: telegram.busy
                    ? null
                    : () => telegram.action(telegram.refreshChats),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Load more'),
              ),
            ],
          ),
          if (telegram.error != null) _banner(telegram.error!),
          Expanded(
            child: chats.isEmpty
                ? _empty(
                    Icons.forum_outlined,
                    'No chats to show',
                    'Join a channel in Telegram, then load your chats here.',
                  )
                : ListView.builder(
                    itemCount: chats.length,
                    itemBuilder: (context, i) => ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF30283E),
                        child: Icon(
                          Icons.forum_rounded,
                          size: 20,
                          color: accent,
                        ),
                      ),
                      title: Text(
                        chats[i].title,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Browse shared audio',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _browse(chats[i]),
                    ),
                  ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () {
                ++_browseGeneration;
                setState(() {
                  chat = null;
                  loading = false;
                  search.clear();
                });
              },
              tooltip: 'All chats',
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Text(
                chat!.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: loading ? null : () => _browse(chat!),
              tooltip: 'Refresh music',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _search('Search loaded tracks'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Music'),
              selected: !documents,
              onSelected: loading
                  ? null
                  : (_) {
                      setState(() {
                        documents = false;
                      });
                      _browse(chat!);
                    },
            ),
            ChoiceChip(
              label: const Text('Audio documents'),
              selected: documents,
              onSelected: loading
                  ? null
                  : (_) {
                      setState(() {
                        documents = true;
                      });
                      _browse(chat!);
                    },
            ),
          ],
        ),
        if (browseError != null) _banner(browseError!),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        Expanded(
          child: telegramTracks.isEmpty && !loading
              ? _empty(
                  Icons.music_off_rounded,
                  'No audio in this page',
                  'Try Audio documents, or load older messages.',
                )
              : _trackList(telegramTracks),
        ),
        if (cursor != 0)
          TextButton(
            onPressed: loading ? null : () => _browse(chat!, more: true),
            child: const Text('Load older audio'),
          ),
      ],
    );
  }

  Widget _signIn() => SingleChildScrollView(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF30283E),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.send_rounded, color: accent, size: 36),
            ),
            const SizedBox(height: 22),
            const Text(
              'Your channels. Your soundtrack.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Connect Telegram to browse music shared in chats you can access. Audio stays on your device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.6, fontSize: 12),
            ),
            const SizedBox(height: 24),
            AuthForm(telegram: telegram),
            const SizedBox(height: 18),
            const Text(
              'Credentials are encrypted for your Windows account.\nLogin codes and passwords are never saved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 10, height: 1.6),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );

  Widget _queue() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '${player.queue.length} tracks',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
          IconButton(
            onPressed: player.queue.isEmpty ? null : player.shuffle,
            tooltip: 'Shuffle upcoming tracks',
            icon: const Icon(Icons.shuffle_rounded),
          ),
          TextButton(
            onPressed: player.queue.isEmpty ? null : () => player.clear(),
            child: const Text('Clear'),
          ),
        ],
      ),
      Expanded(
        child: player.queue.isEmpty
            ? _empty(
                Icons.queue_music_rounded,
                'A little more of what you love',
                'Add tracks from your library or Telegram to build a queue.',
              )
            : ReorderableListView.builder(
                itemCount: player.queue.length,
                buildDefaultDragHandles: false,
                onReorderItem: player.reorder,
                itemBuilder: (context, i) => ReorderableDragStartListener(
                  key: ValueKey('$i:${player.queue[i].id}'),
                  index: i,
                  child: _trackTile(
                    player.queue[i],
                    queued: true,
                    onPlay: () => player.playAt(i),
                  ),
                ),
              ),
      ),
    ],
  );
  Widget _nowPlaying({bool compact = false}) {
    final track = player.current;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'NOW PLAYING',
            style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.8),
          ),
          const SizedBox(height: 22),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 260 : 330),
              child: AspectRatio(
                aspectRatio: 1,
                child: Artwork(seed: track?.title ?? 'Auralis'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            track?.title ?? 'Find your next favorite',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 20 : 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            track?.artist ?? 'A space for the music you love',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Center(
            child: Chip(
              avatar: Icon(
                track?.fileId == null
                    ? Icons.folder_outlined
                    : Icons.send_rounded,
                size: 14,
              ),
              label: Text(
                track?.source ?? 'Nothing playing',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'UP NEXT',
                  style: TextStyle(
                    color: muted,
                    fontSize: 9,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Text(
                '${math.max(0, player.queue.length - player.index - 1)} tracks',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (
            var i = player.index + 1;
            i < math.min(player.queue.length, player.index + 4);
            i++
          )
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.music_note_rounded,
                size: 20,
                color: accent,
              ),
              title: Text(
                player.queue[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                player.queue[i].artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
              onTap: () => player.playAt(i),
            ),
          if (player.queue.length <= player.index + 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Let the next track find its way here.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(
    IconData icon,
    String title,
    String description, {
    Widget? action,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFF25202E),
              borderRadius: BorderRadius.circular(34),
            ),
            child: Icon(icon, size: 38, color: accent),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, height: 1.8, fontSize: 12),
          ),
          if (action != null) ...[const SizedBox(height: 24), action],
        ],
      ),
    ),
  );

  Widget _transport(bool narrow) {
    final audio = player.audio, duration = player.audio.duration.inMilliseconds;
    final progress = duration <= 0
        ? 0.0
        : (audio.position.inMilliseconds / duration).clamp(0.0, 1.0);
    final buffer = duration <= 0
        ? 0.0
        : (audio.buffered.inMilliseconds / duration).clamp(0.0, 1.0);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1A25),
        border: Border(top: BorderSide(color: Color(0xFF302B39))),
      ),
      padding: EdgeInsets.fromLTRB(narrow ? 12 : 24, 10, narrow ? 12 : 24, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                clockText(audio.position),
                style: const TextStyle(fontSize: 10, color: muted),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                  ),
                  child: Slider(
                    value: progress,
                    secondaryTrackValue: math.max(buffer, progress),
                    semanticFormatterCallback: (v) => clockText(
                      Duration(milliseconds: (v * duration).round()),
                    ),
                    onChanged: duration <= 0
                        ? null
                        : (v) => audio.seek(
                            Duration(milliseconds: (v * duration).round()),
                          ),
                  ),
                ),
              ),
              Text(
                clockText(audio.duration),
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
          Row(
            children: [
              SizedBox(
                width: narrow ? 36 : 44,
                height: narrow ? 36 : 44,
                child: Artwork(
                  seed: player.current?.title ?? 'Auralis',
                  small: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.current?.title ?? 'Nothing playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      player.current?.artist ?? 'Choose a track to get started',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (player.loading || audio.buffering)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                onPressed: player.current == null ? null : player.previous,
                tooltip: 'Previous track',
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton.filled(
                onPressed: player.current == null || player.loading
                    ? null
                    : audio.toggle,
                tooltip: audio.playing ? 'Pause' : 'Play',
                icon: Icon(
                  audio.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                onPressed: player.current == null ? null : player.next,
                tooltip: 'Next track',
                icon: const Icon(Icons.skip_next_rounded),
              ),
              if (!narrow) ...[
                const SizedBox(width: 12),
                IconButton(
                  onPressed: player.toggleRepeat,
                  tooltip: 'Repeat queue',
                  icon: Icon(
                    Icons.repeat_rounded,
                    color: player.repeat ? accent : muted,
                  ),
                ),
                const SizedBox(width: 18),
                const Icon(Icons.volume_up_rounded, size: 18, color: muted),
                SizedBox(
                  width: 105,
                  child: Slider(
                    value: player.settings.volume,
                    max: 100,
                    label: '${player.settings.volume.round()}%',
                    onChanged: (v) {
                      player.settings.volume = v;
                      setState(() {});
                    },
                    onChangeEnd: player.setVolume,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _settings() => showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Make it yours'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reduce motion'),
                  subtitle: const Text('Use instant page transitions'),
                  value: player.settings.reducedMotion,
                  onChanged: (v) async {
                    update(() {
                      player.settings.reducedMotion = v;
                    });
                    setState(() {});
                    try {
                      await player.settings.save();
                    } catch (_) {
                      _notice('Could not save settings.');
                    }
                  },
                ),
                const Divider(),
                if (widget.updater != null) ...[
                  UpdateSettings(updater: widget.updater!),
                  const Divider(),
                ],
                Text(
                  'Auralis ${widget.updater?.currentVersion ?? '0.1.0'} · AGPL-3.0-or-later\nIndependent Flutter interface. Playback by libmpv. Telegram connectivity by TDLib.',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
                if (telegram.ready)
                  TextButton(
                    onPressed: () async {
                      await player.clear();
                      await telegram.logout();
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: const Text('Sign out of Telegram'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Auralis',
              applicationVersion: widget.updater?.currentVersion ?? '0.1.0',
            ),
            child: const Text('Licenses'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}

class AuthForm extends StatefulWidget {
  const AuthForm({super.key, required this.telegram});
  final TelegramService telegram;
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final apiId = TextEditingController(),
      apiHash = TextEditingController(),
      value = TextEditingController();
  String? _lastState;
  @override
  void dispose() {
    apiId.dispose();
    apiHash.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final td = widget.telegram;
    if (_lastState != td.state) {
      value.clear();
      _lastState = td.state;
    }
    final initial = td.state == 'disconnected';
    final label = switch (td.state) {
      'authorizationStateWaitPhoneNumber' =>
        'Phone number, including country code',
      'authorizationStateWaitCode' => 'Login code from Telegram',
      'authorizationStateWaitPassword' => 'Two-step verification password',
      'authorizationStateWaitEmailAddress' =>
        'Email address requested by Telegram',
      'authorizationStateWaitEmailCode' => 'Email verification code',
      _ => null,
    };
    Future<void> submit() async {
      if (initial) {
        await td.start(
          apiId: int.tryParse(apiId.text.trim()) ?? 0,
          apiHash: apiHash.text.trim(),
        );
        apiHash.clear();
      } else {
        final input = value.text;
        value.clear();
        await td.submit(input);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (initial) ...[
          const Text(
            'Create an API application at my.telegram.org, then enter its details here.',
            style: TextStyle(fontSize: 12, color: muted, height: 1.6),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: apiId,
            decoration: const InputDecoration(labelText: 'Telegram API ID'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: apiHash,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Telegram API hash'),
          ),
        ] else if (label != null)
          TextField(
            key: ValueKey(td.state),
            controller: value,
            obscureText: td.state == 'authorizationStateWaitPassword',
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: label),
            onSubmitted: td.busy ? null : (_) => submit(),
          )
        else
          Text(switch (td.state) {
            'authorizationStateWaitRegistration' => 'Create your Telegram account in the official app first, then restart Auralis.',
            'authorizationStateClosed' =>
              'Telegram was closed. Restart Auralis to reconnect.',
            'authorizationStateWaitPremiumPurchase' => 'Telegram requires a Premium verification step. Complete it in the official app.',
            'authorizationStateWaitOtherDeviceConfirmation' =>
              'Confirm this sign-in in your Telegram application.',
            _ => 'Connecting securely to Telegram…',
          }, style: const TextStyle(color: muted, height: 1.6)),
        if (td.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              td.error!,
              style: const TextStyle(color: Color(0xFFFFB4C8), fontSize: 12),
            ),
          ),
        const SizedBox(height: 18),
        if (initial || label != null)
          FilledButton(
            onPressed: td.busy ? null : submit,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: td.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(initial ? 'Connect Telegram' : 'Continue'),
            ),
          ),
      ],
    );
  }
}

/// Original procedural artwork; no upstream assets or album covers.
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.seed, this.small = false});
  final String seed;
  final bool small;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(small ? 12 : 30),
    child: CustomPaint(
      painter: _RecordPainter(seed),
      child: const SizedBox.expand(),
    ),
  );
}

class _RecordPainter extends CustomPainter {
  _RecordPainter(this.seed);
  final String seed;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = 240.0 + seed.codeUnits.fold(0, (a, b) => a + b) % 80;
    final dark = HSLColor.fromAHSL(1, hue, .25, .2).toColor(),
        light = HSLColor.fromAHSL(1, hue, .5, .72).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, dark],
        ).createShader(rect),
    );
    final center = Offset(size.width * .62, size.height * .57);
    for (var i = 1; i < 11; i++) {
      canvas.drawCircle(
        center,
        size.width * (.08 + i * .034),
        Paint()
          ..color = Colors.black.withValues(alpha: .13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .012,
      );
    }
    canvas.drawCircle(
      center,
      size.width * .085,
      Paint()..color = const Color(0xFFDAD0E9),
    );
    canvas.drawCircle(center, size.width * .018, Paint()..color = dark);
    final path = Path()
      ..moveTo(0, size.height * .7)
      ..cubicTo(
        size.width * .2,
        size.height * .3,
        size.width * .3,
        size.height * .9,
        size.width,
        size.height * .2,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .11,
    );
  }

  @override
  bool shouldRepaint(_RecordPainter oldDelegate) => seed != oldDelegate.seed;
}
