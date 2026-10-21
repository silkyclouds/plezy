import 'dart:typed_data';

/// Turns recorded speech into text.
abstract interface class VoiceTranscriber {
  /// [wav] is 16 kHz mono 16-bit PCM in a WAV container. [language] is an ISO 639-1 code, or null to let the engine detect it.
  Future<String> transcribe(Uint8List wav, {String? language});
}

/// The recording could not be turned into text. [message] is safe to show to the user.
class VoiceTranscriptionException implements Exception {
  final String message;

  const VoiceTranscriptionException(this.message);

  @override
  String toString() => message;
}
