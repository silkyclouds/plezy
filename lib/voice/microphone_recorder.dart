import 'dart:typed_data';

/// Records the default microphone into a WAV file held in memory.
abstract interface class MicrophoneRecorder {
  /// Whether recording can work on this machine.
  Future<bool> isAvailable();

  /// Starts recording. Throws [MicrophoneException] when no recorder can start.
  Future<void> start();

  /// Stops and returns 16 kHz mono 16-bit WAV bytes.
  Future<Uint8List> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();
}

class MicrophoneException implements Exception {
  final String message;

  const MicrophoneException(this.message);

  @override
  String toString() => message;
}
