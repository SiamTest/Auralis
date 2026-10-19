import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:auralis/app.dart';
import 'package:auralis/player.dart';
import 'package:auralis/storage.dart';
import 'package:auralis/telegram/stream_proxy.dart';
import 'package:auralis/telegram/telegram_service.dart';
import 'package:auralis/updater.dart';

import 'fakes.dart';

void main() {
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    if (await font.exists()) {
      await (FontLoader('Segoe UI')
            ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b))))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'responsive library, queue, Telegram, now playing and settings have no layout errors',
    (tester) async {
      final audio = FakeAudio();
      final player = PlayerController(
        audio,
        TelegramStreamProxy((_) async => {}),
        AppSettings(File('unused')),
      );
      final telegram = TelegramService(Directory('unused'), MemoryVault());
      final updater = AppUpdater(
        currentVersion: '0.1.0',
        directory: Directory('unused'),
        settings: player.settings,
      );
      addTearDown(updater.dispose);
      final boundary = GlobalKey();
      addTearDown(() async {
        await player.shutdown();
      });
      for (final size in [
        const Size(1280, 800),
        const Size(760, 650),
        const Size(520, 560),
      ]) {
        tester.view.resetPhysicalSize();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: AuralisApp(
              player: player,
              telegram: telegram,
              updater: updater,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Make room for your music'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (size.width == 1280) {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('docs/screenshots/library.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byTooltip('Telegram').first);
        await tester.pumpAndSettle();
        expect(find.text('Telegram API ID'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Play queue').first);
        await tester.pumpAndSettle();
        expect(find.text('A little more of what you love'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Now playing').first);
        await tester.pumpAndSettle();
        expect(find.text('Find your next favorite'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Reduce motion'), findsOneWidget);
        expect(find.text('Check automatically'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Library').first);
        await tester.pumpAndSettle();
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
