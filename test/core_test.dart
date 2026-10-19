import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:auralis/models.dart';
import 'package:auralis/player.dart';
import 'package:auralis/storage.dart';
import 'package:auralis/telegram/stream_proxy.dart';

import 'fakes.dart';

void main() {
  test('Telegram audio and audio documents preserve metadata; other documents are rejected', () {
    final message = <String, dynamic>{
      'id': 100,
      'chat_id': -20,
      'content': {
        '@type': 'messageAudio',
        'audio': {
          'title': 'Night drive',
          'performer': 'Example artist',
          'duration': 210,
          'file_name': 'night.mp3',
          'mime_type': 'audio/mpeg',
          'audio': {'id': 7, 'size': 5000},
        },
      },
    };
    final track = Track.fromMessage(message, 'My channel')!;
    expect(track.title, 'Night drive');
    expect(track.fileId, 7);
    expect(track.duration.inSeconds, 210);
    message['content'] = {
      '@type': 'messageDocument',
      'document': {
        'file_name': 'music.FLAC',
        'document': {'id': 8, 'size': 10},
      },
    };
    expect(Track.fromMessage(message, 'Chat')!.title, 'music');
    message['content']['document']['file_name'] = 'readme.pdf';
    expect(Track.fromMessage(message, 'Chat'), isNull);
    message['content'] = {'@type': 'messageVoiceNote'};
    expect(Track.fromMessage(message, 'Chat'), isNull);
  });

  test('settings serialize rapid writes and clamp persisted volume', () async {
    final dir = await Directory.systemTemp.createTemp('auralis-settings-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/settings.json');
    final settings = AppSettings(file)
      ..volume = 23
      ..reducedMotion = true
      ..localFiles = ['C:/Music/song.wav'];
    final first = settings.save();
    settings.volume = 45;
    final last = settings.save();
    await Future.wait([first, last]);
    final restored = AppSettings(file);
    await restored.load();
    expect(restored.volume, 45);
    expect(restored.reducedMotion, isTrue);
    expect(restored.localFiles.single, 'C:/Music/song.wav');
    await file.writeAsString(jsonEncode({'volume': 200}));
    await restored.load();
    expect(restored.volume, 100);
  });

  test(
    'Windows DPAPI vault encrypts and restores secrets; rejects tampering',
    () async {
      final dir = await Directory.systemTemp.createTemp('auralis-vault-');
      addTearDown(() => dir.delete(recursive: true));
      final vault = SecretVault(File('${dir.path}/vault.dpapi'));
      await vault.write({
        'apiHash': 'test-only-value',
        'databaseKey': SecretVault.newDatabaseKey(),
      });
      expect((await vault.read())['apiHash'], 'test-only-value');
      expect(
        latin1
            .decode(await vault.file.readAsBytes())
            .contains('test-only-value'),
        isFalse,
      );
      final damaged = await vault.file.readAsBytes();
      damaged[damaged.length ~/ 2] ^= 1;
      await vault.file.writeAsBytes(damaged);
      await expectLater(vault.read(), throwsA(isA<FileSystemException>()));
    },
    skip: !Platform.isWindows,
  );

  test('queue advances across duplicate tracks, preserves playing item on reorder, and clears', () async {
    final audio = FakeAudio();
    final proxy = TelegramStreamProxy((_) async => {});
    final player = PlayerController(audio, proxy, AppSettings(File('unused')));
    addTearDown(player.shutdown);
    final a = Track.local('C:/a.wav'), b = Track.local('C:/b.wav');
    player.enqueue(a);
    player.enqueue(a);
    player.enqueue(b);
    await player.playAt(0);
    await player.next();
    expect(player.index, 1);
    player.reorder(1, 0);
    expect(player.index, 0);
    player.reorder(0, 1);
    expect(player.index, 1);
    await player.next();
    expect(player.current, b);
    expect(audio.uri, b.path);
    player.reorder(2, 0);
    expect(player.index, 0);
    expect(player.current, b);
    await player.playAt(2);
    player.toggleRepeat();
    await player.next();
    expect(player.index, 0);
    audio.position = const Duration(seconds: 12);
    await player.previous();
    expect(audio.position, Duration.zero);
    await player.clear();
    expect(player.current, isNull);
    expect(player.queue, isEmpty);
    expect(audio.playing, isFalse);
  });
}
