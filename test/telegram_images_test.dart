import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:auralis/telegram/td_transport.dart';
import 'package:auralis/telegram/telegram_service.dart';

import 'fakes.dart';

void main() {
  late Directory dir;
  late FakeTd td;
  late TelegramService service;
  late File photo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('auralis-photos-');
    photo = await File('assets/branding/auralis.png')
        .copy('${dir.path}/photo.png');
    td = FakeTd();
    service = TelegramService(dir, MemoryVault(), transport: td);
    await service.start(
      apiId: 12345,
      apiHash: 'abcdef0123456789abcdef0123456789',
    );
    service.state = 'authorizationStateReady';
    td.onRequest = (r) async => r['@type'] == 'downloadFile'
        ? {
            'local': {'path': photo.path, 'is_downloading_completed': true},
          }
        : null;
  });
  tearDown(() async {
    await service.shutdown();
    await dir.delete(recursive: true);
  });

  test(
    'visible artwork downloads are shared and lower priority than playback',
    () async {
      final first = service.image(90);
      final second = service.image(90);
      expect(identical(first, second), isTrue);
      expect(await first, photo.path);
      expect(await second, photo.path);
      final requests = td.requests
          .where((r) => r['@type'] == 'downloadFile')
          .toList();
      expect(requests, hasLength(1));
      expect(requests.single, {
        '@type': 'downloadFile',
        'file_id': 90,
        'priority': 1,
        'offset': 0,
        'limit': 0,
        'synchronous': true,
      });
    },
  );

  test(
    'channel photo changes and removals preserve titles and channel filtering',
    () async {
      td.events.add({
        '@type': 'updateNewChat',
        'chat': {
          'id': -1,
          'title': 'Music',
          'type': {'@type': 'chatTypeSupergroup', 'is_channel': true},
          'photo': {
            'small': {'id': 11},
          },
        },
      });
      expect(service.channels.single.photoFileId, 11);
      td.events.add({
        '@type': 'updateChatTitle',
        'chat_id': -1,
        'title': 'Albums',
      });
      expect(service.channels.single.photoFileId, 11);
      td.events.add({
        '@type': 'updateChatPhoto',
        'chat_id': -1,
        'photo': {
          'small': {'id': 12},
        },
      });
      expect(service.channels.single.photoFileId, 12);
      expect(service.channels.single.title, 'Albums');
      td.events.add({
        '@type': 'updateChatPhoto',
        'chat_id': -2,
        'photo': {
          'small': {'id': 99},
        },
      });
      expect(service.channels, hasLength(1));
      td.events.add({'@type': 'updateChatPhoto', 'chat_id': -1, 'photo': null});
      expect(service.channels.single.photoFileId, isNull);
    },
  );

  test(
    'missing, incomplete and failed artwork falls back; refresh can retry',
    () async {
      final normal = td.onRequest!;
      td.onRequest = (r) async => {
        'local': {'path': photo.path, 'is_downloading_completed': false},
      };
      expect(await service.image(1), isNull);
      td.onRequest = (r) async => {
        'local': {
          'path': '${dir.path}/missing.png',
          'is_downloading_completed': true,
        },
      };
      expect(await service.image(2), isNull);
      td.onRequest = (r) async => throw TimeoutException('test timeout');
      expect(await service.image(3), isNull);
      service.clearImageCache();
      td.onRequest = normal;
      expect(await service.image(3), photo.path);
    },
  );

  test('sign-out invalidates an artwork request still in flight', () async {
    final pending = Completer<Json>();
    td.onRequest = (r) async =>
        r['@type'] == 'downloadFile' ? pending.future : null;
    final request = service.image(1);
    td.auth('authorizationStateLoggingOut');
    pending.complete({
      'local': {'path': photo.path, 'is_downloading_completed': true},
    });
    expect(await request, isNull);
    expect(await service.image(2), isNull);
  });

  test(
    'artwork request cache is bounded instead of retaining every viewed cover',
    () async {
      for (var id = 1; id <= 129; id++) {
        expect(await service.image(id), photo.path);
      }
      await service.image(129);
      await service.image(1);
      expect(
        td.requests.where((r) => r['@type'] == 'downloadFile'),
        hasLength(130),
      );
    },
  );
}
