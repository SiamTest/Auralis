import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'player.dart';
import 'storage.dart';
import 'telegram/stream_proxy.dart';
import 'telegram/telegram_service.dart';
import 'updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  RandomAccessFile? lock;
  try {
    final root = await getApplicationSupportDirectory();
    await root.create(recursive: true);
    lock = await File(p.join(root.path, 'session.lock'))
        .open(mode: FileMode.append);
    await lock.lock(FileLock.exclusive);
    final settings = AppSettings(File(p.join(root.path, 'settings.json')));
    String? warning;
    try {
      await settings.load();
    } catch (_) {
      warning = 'Settings could not be read. Defaults are active; your audio files are unchanged.';
    }
    final vault = SecretVault(File(p.join(root.path, 'credentials.dpapi')));
    final telegram = TelegramService(
      Directory(p.join(root.path, 'telegram')),
      vault,
    );
    final audio = MpvBackend();
    await audio.volume(settings.volume);
    final player = PlayerController(
      audio,
      TelegramStreamProxy(telegram.transport.request),
      settings,
    );
    final package = await PackageInfo.fromPlatform();
    final updater = AppUpdater(
      currentVersion: package.version,
      directory: Directory(p.join(root.path, 'updates')),
      settings: settings,
      requestExit: () async =>
          await ServicesBinding.instance.exitApplication(
            AppExitType.cancelable,
          ) ==
          AppExitResponse.exit,
    );
    AppLifecycleListener(
      onExitRequested: () async {
        try {
          await player.shutdown();
        } finally {
          try {
            await telegram.shutdown();
          } finally {
            updater.dispose();
            await lock?.close();
          }
        }
        return AppExitResponse.exit;
      },
    );
    runApp(
      AuralisApp(
        player: player,
        telegram: telegram,
        startupWarning: warning,
        updater: updater,
      ),
    );
    updater.start();
    if (await vault.file.exists()) unawaited(telegram.start());
  } catch (_) {
    await lock?.close();
    runApp(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: SelectableText(
                'Auralis could not start.\n\nClose any other Auralis window. '
                'If this persists, extract the complete Windows bundle, including libmpv-2.dll and the data folder. '
                'Check that your application data folder is writable.\n\nSee README.md for setup instructions.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
