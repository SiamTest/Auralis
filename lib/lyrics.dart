import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics(
    this.plain,
    this.lines, {
    this.instrumental = false,
    this.online = false,
  });
  final String plain;
  final List<LyricLine> lines;
  final bool instrumental, online;

  static Lyrics parse(
    String text, {
    String? plain,
    bool online = false,
    bool instrumental = false,
  }) {
    if (text.length > 256 * 1024 || (plain?.length ?? 0) > 256 * 1024) {
      throw const FormatException('Lyrics are too long.');
    }
    final rows = text.split(RegExp(r'\r?\n'));
    if (rows.length > 2000) {
      throw const FormatException('Too many lyric lines.');
    }
    final offsetTag = RegExp(
      r'\[offset:([+-]?\d+)\]',
      caseSensitive: false,
    ).firstMatch(text);
    final offset = int.tryParse(offsetTag?[1] ?? '') ?? 0;
    final stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final lines = <LyricLine>[];
    for (final row in rows) {
      final times = stamp.allMatches(row).toList();
      final words = row
          .replaceAll(stamp, '')
          .replaceAll(RegExp(r'<\d+:\d+(?:\.\d+)?>'), '')
          .trim();
      for (final time in times) {
        final seconds = int.parse(time[2]!);
        if (seconds >= 60) continue;
        final fraction = (time[3] ?? '').padRight(3, '0');
        final ms =
            int.parse(time[1]!) * 60000 +
            seconds * 1000 +
            int.parse(fraction) +
            offset;
        lines.add(
          LyricLine(
            Duration(milliseconds: ms.clamp(0, 24 * 60 * 60 * 1000)),
            words,
          ),
        );
        if (lines.length > 2000) {
          throw const FormatException('Too many lyric lines.');
        }
      }
    }
    // Stable ordering preserves simultaneous translation/original lines.
    final times = lines.map((line) => line.time).toSet().toList()..sort();
    final grouped = <LyricLine>[
      for (final time in times)
        LyricLine(
          time,
          lines
              .where((line) => line.time == time)
              .map((line) => line.text)
              .join('\n')
              .trim(),
        ),
    ];
    final fallback = grouped.isEmpty
        ? rows
              .where(
                (row) => !RegExp(
                  r'^\s*\[[a-z]+:.*\]\s*$',
                  caseSensitive: false,
                ).hasMatch(row),
              )
              .join('\n')
              .trim()
        : grouped.map((line) => line.text).join('\n');
    return Lyrics(
      (plain?.trim().isNotEmpty ?? false) ? plain!.trim() : fallback,
      grouped,
      online: online,
      instrumental: instrumental,
    );
  }

  int activeAt(Duration position) {
    var low = 0, high = lines.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }
}

/// Session-only cache; lookup happens only after the user presses Find lyrics.
class LyricsRepository {
  LyricsRepository({HttpClient Function()? createClient})
    : _createClient = createClient ?? HttpClient.new;
  final HttpClient Function() _createClient;
  final _cache = <String, Lyrics?>{};
  final _clients = <HttpClient>{};
  bool _closed = false;
  String _key(Track track) => jsonEncode([
    track.id,
    track.title,
    track.artist,
    track.duration.inSeconds,
  ]);
  bool contains(Track track) => _cache.containsKey(_key(track));
  Lyrics? cached(Track track) => _cache[_key(track)];
  void save(Track track, Lyrics? lyrics) {
    if (_closed) return;
    _cache.remove(_key(track));
    _cache[_key(track)] = lyrics;
    if (_cache.length > 32) _cache.remove(_cache.keys.first);
  }

  Future<Lyrics?> find(Track track) async {
    if (_closed) throw StateError('Lyrics lookup is closed.');
    final title = track.title.trim(), artist = track.artist.trim();
    if (title.isEmpty ||
        artist.isEmpty ||
        title.length > 1000 ||
        artist.length > 1000) {
      throw const FormatException(
        'A song title and artist are needed for lookup.',
      );
    }
    final client = _createClient();
    _clients.add(client);
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final lyrics = await (() async {
        final uri = Uri.https('lrclib.net', '/api/get', {
          'track_name': title,
          'artist_name': artist,
          if (track.duration.inSeconds >= 1 && track.duration.inSeconds <= 3600)
            'duration': '${track.duration.inSeconds}',
        });
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set('Accept', 'application/json');
        request.headers.set(
          'User-Agent',
          'Auralis (https://github.com/SiamTest/Auralis)',
        );
        final response = await request.close();
        if (response.statusCode == 404) return null;
        if (response.statusCode != 200) {
          throw const HttpException(
            'Lyrics service is unavailable. Try again later.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 512 * 1024) {
            throw const FormatException('Lyrics response is too large.');
          }
          bytes.addAll(chunk);
        }
        final data = jsonDecode(utf8.decode(bytes));
        if (data is! Map<String, dynamic> ||
            (data['plainLyrics'] != null && data['plainLyrics'] is! String) ||
            (data['syncedLyrics'] != null && data['syncedLyrics'] is! String)) {
          throw const FormatException(
            'The lyrics service returned an invalid response.',
          );
        }
        final result = Lyrics.parse(
          data['syncedLyrics'] as String? ?? '',
          plain: data['plainLyrics'] as String?,
          online: true,
          instrumental: data['instrumental'] == true,
        );
        return result.plain.isEmpty &&
                result.lines.isEmpty &&
                !result.instrumental
            ? null
            : result;
      })().timeout(const Duration(seconds: 20));
      save(track, lyrics);
      return lyrics;
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
    _cache.clear();
  }
}
