import 'dart:convert';

import 'package:auralis/lyrics.dart';
import 'package:auralis/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'updater_test.dart' show Client, Response;

const song = Track(
  id: 'private-message-id',
  title: 'Evening waves',
  artist: 'Test artist',
  source: 'Private channel',
  duration: Duration(seconds: 120),
);

void main() {
  test('LRC sorts repeated timestamps, merges translations, supports fractions and gaps', () {
    final lyrics = Lyrics.parse(
      '[ar:Test]\n[offset:-50]\n[00:12.5][00:25.123]Evening waves\n[00:02]Small lights\n[00:12.50]Translation\n[00:20.00]\n[01:99]Invalid',
    );
    expect(lyrics.lines.map((line) => line.time.inMilliseconds), [
      1950,
      12450,
      19950,
      25073,
    ]);
    expect(lyrics.lines[1].text, 'Evening waves\nTranslation');
    expect(lyrics.lines[2].text, '');
    expect(lyrics.activeAt(Duration.zero), -1);
    expect(lyrics.activeAt(const Duration(milliseconds: 12450)), 1);
    expect(lyrics.activeAt(const Duration(minutes: 2)), 3);
    expect(lyrics.plain, isNot(contains('[ar:')));
    expect(
      Lyrics.parse('[00:00] <00:00.10>Small <00:00.30>lights').plain,
      'Small lights',
    );
  });

  test('plain lyrics, bounds and negative offsets are handled', () {
    expect(Lyrics.parse('Original words\nAnother line').lines, isEmpty);
    expect(
      Lyrics.parse('[00:00.01]Early\n[offset:-500]').lines.single.time,
      Duration.zero,
    );
    expect(() => Lyrics.parse('a' * (256 * 1024 + 1)), throwsFormatException);
    expect(
      () => Lyrics.parse(List.filled(2001, 'line').join('\n')),
      throwsFormatException,
    );
  });

  test(
    'lookup sends only song metadata and closes HTTP; cache is session bounded',
    () async {
      final client = Client([
        Response(
          utf8.encode(
            jsonEncode({
              'syncedLyrics': '[00:02.00]Original test words',
              'plainLyrics': 'Original test words',
              'instrumental': false,
            }),
          ),
        ),
      ]);
      final repository = LyricsRepository(createClient: () => client);
      expect(client.requests, isEmpty);
      final result = await repository.find(song);
      expect(result!.online, isTrue);
      expect(client.requests.single.scheme, 'https');
      expect(client.requests.single.host, 'lrclib.net');
      expect(client.requests.single.queryParameters, {
        'track_name': 'Evening waves',
        'artist_name': 'Test artist',
        'duration': '120',
      });
      expect(client.requests.single.toString(), isNot(contains('Private')));
      expect(client.closed, isTrue);
      expect(repository.cached(song), same(result));
      for (var i = 0; i < 33; i++) {
        repository.save(
          Track(id: '$i', title: 'Title', artist: 'Artist', source: 'Channel'),
          result,
        );
      }
      expect(repository.contains(song), isFalse);
      repository.close();
      expect(() => repository.find(song), throwsStateError);
    },
  );

  test('not found and instrumental states differ; invalid/oversized HTTP never caches', () async {
    for (final response in [
      Response([], statusCode: 404),
      Response(utf8.encode('{"instrumental":true}')),
      Response([], statusCode: 302, redirect: 'https://example.com/'),
      Response(utf8.encode('{"plainLyrics":42}')),
      Response(List.filled(512 * 1024 + 1, 32)),
      Response(utf8.encode('not json')),
    ]) {
      final client = Client([response]);
      final repository = LyricsRepository(createClient: () => client);
      if (response.statusCode == 404) {
        expect(await repository.find(song), isNull);
        expect(repository.contains(song), isTrue);
      } else if (response.bytes.length < 40 &&
          response.statusCode == 200 &&
          utf8.decode(response.bytes).contains('true')) {
        expect((await repository.find(song))!.instrumental, isTrue);
      } else {
        await expectLater(repository.find(song), throwsException);
        expect(repository.contains(song), isFalse);
      }
      expect(client.closed, isTrue);
      repository.close();
    }
  });
}
