import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'models.dart';
import 'storage.dart';
import 'telegram/stream_proxy.dart';

abstract class AudioBackend extends ChangeNotifier {
  bool playing = false, buffering = false;
  Duration position = Duration.zero,
      duration = Duration.zero,
      buffered = Duration.zero;
  String? error;
  VoidCallback? onCompleted;
  Future<void> open(String uri);
  Future<void> toggle();
  Future<void> seek(Duration value);
  Future<void> volume(double value);
  Future<void> stop();
  Future<void> shutdown();
}

class MpvBackend extends AudioBackend {
  MpvBackend() {
    MediaKit.ensureInitialized();
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Auralis',
        bufferSize: 8 * 1024 * 1024,
      ),
    );
    _subscriptions.addAll([
      _player.stream.playing.listen((v) {
        playing = v;
        notifyListeners();
      }),
      _player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      _player.stream.position.listen((v) {
        position = v;
        notifyListeners();
      }),
      _player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
      }),
      _player.stream.buffer.listen((v) {
        buffered = v;
        notifyListeners();
      }),
      _player.stream.error.listen((_) {
        error = 'Audio could not be decoded or the source is unavailable.';
        notifyListeners();
      }),
      _player.stream.completed.listen((v) {
        if (v) onCompleted?.call();
      }),
    ]);
  }
  late final Player _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  @override
  Future<void> open(String uri) async {
    error = null;
    position = Duration.zero;
    duration = Duration.zero;
    await _player.open(Media(uri));
  }

  @override
  Future<void> toggle() => _player.playOrPause();
  @override
  Future<void> seek(Duration value) async {
    await _player.seek(value);
    position = value;
    notifyListeners();
  }

  @override
  Future<void> volume(double value) => _player.setVolume(value);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> shutdown() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    dispose();
  }
}

class PlayerController extends ChangeNotifier {
  PlayerController(this.audio, this.proxy, this.settings) {
    audio.addListener(notifyListeners);
    audio.onCompleted = () => unawaited(next(automatic: true));
    _proxyErrors = proxy.errors.listen((value) {
      error = value;
      notifyListeners();
    });
  }
  final AudioBackend audio;
  final TelegramStreamProxy proxy;
  final AppSettings settings;
  late final StreamSubscription<String> _proxyErrors;
  final List<Track> queue = [];
  int index = -1, _generation = 0;
  bool loading = false, repeat = false;
  String? error;
  Track? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;

  void toggleRepeat() {
    repeat = !repeat;
    notifyListeners();
  }

  Future<void> playAt(int target) async {
    if (target < 0 || target >= queue.length) return;
    index = target;
    await _open(queue[target]);
  }

  Future<void> play(Track track, {List<Track>? from}) async {
    if (from != null) {
      queue
        ..clear()
        ..addAll(from);
      index = queue.indexWhere((t) => t.id == track.id);
    } else {
      index = queue.indexWhere((t) => t.id == track.id);
      if (index < 0) {
        queue.add(track);
        index = queue.length - 1;
      }
    }
    if (index < 0) return;
    await _open(track);
  }

  Future<void> _open(Track track) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final uri = (await proxy.uri(track)).toString();
      if (generation != _generation) return;
      await audio.open(uri);
    } catch (_) {
      if (generation == _generation) error = 'Could not open this track. Check the Telegram connection and native libraries.';
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void enqueue(Track track) {
    queue.add(track);
    notifyListeners();
  }

  Future<void> next({bool automatic = false}) async {
    if (queue.isEmpty) return;
    if (index + 1 < queue.length) {
      await playAt(index + 1);
    } else if (repeat) {
      await playAt(0);
    } else if (!automatic && current == null) {
      await playAt(0);
    }
  }

  Future<void> previous() async {
    if (audio.position > const Duration(seconds: 3)) {
      await audio.seek(Duration.zero);
    } else if (index > 0) {
      await playAt(index - 1);
    }
  }

  void reorder(int oldIndex, int newIndex) {
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    if (index == oldIndex) {
      index = newIndex;
    } else if (oldIndex < index && newIndex >= index) {
      index--;
    } else if (oldIndex > index && newIndex <= index) {
      index++;
    }
    notifyListeners();
  }

  void shuffle() {
    final upcoming = queue.skip(index + 1).toList()..shuffle(Random.secure());
    queue.replaceRange(index + 1, queue.length, upcoming);
    notifyListeners();
  }

  Future<void> setVolume(double value, {bool persist = true}) async {
    final volume = value.clamp(0.0, 100.0);
    settings.volume = volume;
    notifyListeners();
    try {
      await audio.volume(volume);
      if (persist) await settings.save();
    } catch (_) {
      error = 'Could not apply or save the volume setting.';
      notifyListeners();
    }
  }

  Future<void> clear() async {
    ++_generation;
    loading = false;
    await audio.stop();
    await proxy.stop();
    queue.clear();
    index = -1;
    notifyListeners();
  }

  Future<void> shutdown() async {
    ++_generation;
    await _proxyErrors.cancel();
    audio.removeListener(notifyListeners);
    await audio.shutdown();
    await proxy.close();
    dispose();
  }
}
