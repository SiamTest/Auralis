import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import '../storage.dart';
import 'td_transport.dart';

class TelegramService extends ChangeNotifier {
  TelegramService(this.directory, this.vault, {TdTransport? transport})
    : transport = transport ?? TdTransport();
  final Directory directory;
  final SecretVault vault;
  final TdTransport transport;
  StreamSubscription<Json>? _subscription;
  Json _secrets = {};
  String state = 'disconnected';
  String? error;
  bool busy = false;
  final Map<int, MusicChat> _chats = {};
  List<MusicChat> get chats => _chats.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  bool get ready => state == 'authorizationStateReady';
  String connection = 'Offline';

  Future<void> start({int? apiId, String? apiHash}) async {
    await action(() async {
      _secrets = await vault.read();
      if (apiId != null) _secrets['apiId'] = apiId;
      if (apiHash != null) _secrets['apiHash'] = apiHash;
      if ((_secrets['apiId'] as int? ?? 0) <= 0 ||
          !RegExp(r'^[a-fA-F0-9]{32}$')
              .hasMatch(_secrets['apiHash'] as String? ?? '')) {
        throw const FormatException(
          'Enter your Telegram API ID and 32-character API hash from my.telegram.org.',
        );
      }
      _secrets.putIfAbsent('databaseKey', SecretVault.newDatabaseKey);
      await vault.write(_secrets);
      await directory.create(recursive: true);
      await _subscription?.cancel();
      _subscription = transport.updates.listen(_onUpdate);
      final native = p.join(
        p.dirname(Platform.resolvedExecutable),
        'native',
        'tdjson.dll',
      );
      await transport.start(native);
      state = 'connecting';
      final auth = await transport.request({'@type': 'getAuthorizationState'});
      await _onAuthorization(auth);
    });
  }

  void _onUpdate(Json json) {
    switch (json['@type']) {
      case 'updateAuthorizationState':
        unawaited(
          _onAuthorization(json['authorization_state'] as Json)
              .catchError((Object _) {
                error = 'Telegram initialization failed. Check your API credentials and network.';
                notifyListeners();
              }),
        );
      case 'updateNewChat':
        final chat = json['chat'] as Json;
        _chats[chat['id'] as int] = MusicChat(
          chat['id'] as int,
          chat['title'] as String,
        );
        notifyListeners();
      case 'updateChatTitle':
        final id = json['chat_id'] as int;
        _chats[id] = MusicChat(id, json['title'] as String);
        notifyListeners();
      case 'updateConnectionState':
        connection = switch (json['state']?['@type']) {
          'connectionStateReady' => 'Connected',
          'connectionStateUpdating' => 'Syncing',
          'connectionStateWaitingForNetwork' => 'Waiting for network',
          _ => 'Connecting',
        };
        notifyListeners();
    }
  }

  bool _parametersSent = false;
  Future<void> _onAuthorization(Json auth) async {
    state = auth['@type'] as String;
    error = null;
    notifyListeners();
    if (state == 'authorizationStateWaitTdlibParameters' && !_parametersSent) {
      _parametersSent = true;
      try {
        await transport.request({
          '@type': 'setTdlibParameters',
          'use_test_dc': false,
          'database_directory': p.join(directory.path, 'database'),
          'files_directory': p.join(directory.path, 'cache'),
          'database_encryption_key': _secrets['databaseKey'],
          'use_file_database': true,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'api_id': _secrets['apiId'],
          'api_hash': _secrets['apiHash'],
          'system_language_code': 'en',
          'device_model': 'Auralis Windows x64',
          'system_version': 'Windows',
          'application_version': '0.1.0',
        });
      } catch (_) {
        _parametersSent = false;
        rethrow;
      }
    } else if (ready) {
      await refreshChats();
    }
  }

  Future<void> submit(String value) => action(() async {
    final request = switch (state) {
      'authorizationStateWaitPhoneNumber' => {
        '@type': 'setAuthenticationPhoneNumber',
        'phone_number': value.trim(),
      },
      'authorizationStateWaitCode' => {
        '@type': 'checkAuthenticationCode',
        'code': value.trim(),
      },
      'authorizationStateWaitPassword' => {
        '@type': 'checkAuthenticationPassword',
        'password': value,
      },
      'authorizationStateWaitEmailAddress' => {
        '@type': 'setAuthenticationEmailAddress',
        'email_address': value.trim(),
      },
      'authorizationStateWaitEmailCode' => {
        '@type': 'checkAuthenticationEmailCode',
        'code': {
          '@type': 'emailAddressAuthenticationCode',
          'code': value.trim(),
        },
      },
      _ => throw StateError(
        'Complete this sign-in step in the official Telegram application.',
      ),
    };
    if (value.isEmpty) {
      throw const FormatException('Enter a value to continue.');
    }
    await transport.request(request);
  });

  Future<void> refreshChats() async {
    for (final type in ['chatListMain', 'chatListArchive']) {
      try {
        await transport.request({
          '@type': 'loadChats',
          'chat_list': {'@type': type},
          'limit': 100,
        });
      } on TdException catch (e) {
        if (e.code != 404) rethrow;
      }
    }
  }

  Future<List<Track>> music(
    int chatId,
    String title, {
    int before = 0,
    bool documents = false,
  }) async {
    final result = await transport.request({
      '@type': 'searchChatMessages',
      'chat_id': chatId,
      'topic_id': null,
      'query': '',
      'sender_id': null,
      'from_message_id': before,
      'offset': 0,
      'limit': 100,
      'filter': {
        '@type': documents
            ? 'searchMessagesFilterDocument'
            : 'searchMessagesFilterAudio',
      },
    });
    nextMessageId = (result['next_from_message_id'] as int?) ?? 0;
    return (result['messages'] as List)
        .map((m) => Track.fromMessage(m as Json, title))
        .whereType<Track>()
        .toList();
  }

  int nextMessageId = 0;

  Future<void> logout() => action(() async {
    await transport.request({'@type': 'logOut'});
    _chats.clear();
  });

  Future<void> action(Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (e) {
      error = e is FormatException
          ? e.message
          : e is TdException
          ? 'Telegram rejected the request (${e.code}). Check the value and try again; Telegram may require a wait.'
          : e is StateError
          ? e.message.toString()
          : 'Could not connect. Check native/tdjson.dll, credentials, and network.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> shutdown() async {
    await _subscription?.cancel();
    await transport.close();
  }
}
