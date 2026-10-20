import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'data_backup.dart';
import 'storage.dart';

class DataFiles {
  const DataFiles();

  Future<String?> savePath(String name, String extension) async =>
      (await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: [
          XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
        ],
      ))?.path;

  Future<String?> openBackup() async => (await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Auralis backup', extensions: ['json']),
    ],
  ))?.path;

  Future<String> read(String path) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead(0, DataBackup.maxBytes + 1)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length > DataBackup.maxBytes) {
      throw const FormatException('Backup exceeds 64 MiB.');
    }
    return utf8.decode(bytes);
  }

  Future<void> write(String path, String text) =>
      atomicWrite(File(path), utf8.encode(text));
}
