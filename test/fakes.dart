import 'dart:io';

import 'package:auralis/player.dart';
import 'package:auralis/storage.dart';

class FakeAudio extends AudioBackend {
  String? uri;
  @override
  Future<void> open(String uri) async {
    this.uri = uri;
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> toggle() async {
    playing = !playing;
    notifyListeners();
  }

  @override
  Future<void> volume(double value) async {}
  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> shutdown() async {
    dispose();
  }
}

class MemoryVault extends SecretVault {
  MemoryVault() : super(File('unused.dpapi'));
  Map<String, dynamic> data = {};
  @override
  Future<Map<String, dynamic>> read() async => {...data};
  @override
  Future<void> write(Map<String, dynamic> secrets) async {
    data = {...secrets};
  }
}
