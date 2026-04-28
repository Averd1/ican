import 'package:flutter/services.dart';

abstract interface class Mp3AudioPlayer {
  Future<void> playMp3(Uint8List bytes);
  Future<void> stop();
}

class NativeMp3AudioPlayer implements Mp3AudioPlayer {
  NativeMp3AudioPlayer({
    MethodChannel channel = const MethodChannel('com.ican/audio_player'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> playMp3(Uint8List bytes) async {
    await _channel.invokeMethod<bool>('playMp3', {'bytes': bytes});
  }

  @override
  Future<void> stop() async {
    await _channel.invokeMethod<bool>('stop');
  }
}
