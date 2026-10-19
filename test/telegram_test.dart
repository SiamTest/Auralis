import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:auralis/telegram/td_transport.dart';
import 'package:auralis/telegram/telegram_service.dart';

import 'fakes.dart';

class FakeTd extends TdTransport {
  final events = StreamController<Json>.broadcast(sync: true);
  final requests = <Json>[];
  @override
  Stream<Json> get updates => events.stream;
  @override
  Future<void> start(String libraryPath) async {}
  @override
  Future<Json> request(
    Json json, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requests.add(json);
    if (json['@type'] == 'getAuthorizationState') {
      return {'@type': 'authorizationStateWaitTdlibParameters'};
    }
    if (json['@type'] == 'searchChatMessages') {
      return {'messages': [], 'next_from_message_id': 777};
    }
    return {'@type': 'ok'};
  }

  void auth(String state) => events.add({
    '@type': 'updateAuthorizationState',
    'authorization_state': {'@type': state},
  });
  @override
  Future<void> close() async {
    await events.close();
  }
}

void main() {
  test('auth drives phone, code and 2FA with encrypted database parameters; codes are not stored', () async {
    final dir = await Directory.systemTemp.createTemp('auralis-auth-');
    addTearDown(() => dir.delete(recursive: true));
    final td = FakeTd(), vault = MemoryVault();
    final service = TelegramService(dir, vault, transport: td);
    addTearDown(service.shutdown);
    await service.start(
      apiId: 12345,
      apiHash: 'abcdef0123456789abcdef0123456789',
    );
    final parameters = td.requests.firstWhere(
      (r) => r['@type'] == 'setTdlibParameters',
    );
    expect(parameters['database_encryption_key'], isNotEmpty);
    expect(parameters['use_secret_chats'], isFalse);
    td.auth('authorizationStateWaitPhoneNumber');
    await service.submit('+12025550123');
    expect(td.requests.last['@type'], 'setAuthenticationPhoneNumber');
    td.auth('authorizationStateWaitCode');
    await service.submit('12345');
    expect(td.requests.last, {
      '@type': 'checkAuthenticationCode',
      'code': '12345',
    });
    td.auth('authorizationStateWaitPassword');
    await service.submit('sample-password');
    expect(td.requests.last['@type'], 'checkAuthenticationPassword');
    expect(vault.data.keys.toSet(), {'apiId', 'apiHash', 'databaseKey'});
    td.auth('authorizationStateReady');
    await Future<void>.delayed(Duration.zero);
    expect(td.requests.where((r) => r['@type'] == 'loadChats').length, 2);
    td.events.add({
      '@type': 'updateNewChat',
      'chat': {'id': 1, 'title': 'Music'},
    });
    expect(service.chats.single.title, 'Music');
    await service.music(1, 'Music', documents: true, before: 123);
    expect(td.requests.last['filter']['@type'], 'searchMessagesFilterDocument');
    expect(td.requests.last['from_message_id'], 123);
    expect(service.nextMessageId, 777);
  });
  test(
    'invalid credentials fail before any native client is started',
    () async {
      final td = FakeTd();
      final service = TelegramService(
        Directory('unused'),
        MemoryVault(),
        transport: td,
      );
      addTearDown(service.shutdown);
      await service.start(apiId: -1, apiHash: 'invalid');
      expect(service.error, contains('API ID'));
      expect(td.requests, isEmpty);
    },
  );
}
