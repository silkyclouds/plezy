import 'dart:io' show Platform;

import '../services/settings_service.dart';
import 'microphone_recorder.dart';
import 'pulse_microphone_recorder.dart';
import 'voice_search_controller.dart';
import 'whisper_http_transcriber.dart';

/// Builds a voice search controller from the user's settings, or null when voice search cannot work here.
class VoiceSearchFactory {
  final MicrophoneRecorder? Function() _recorderForPlatform;

  const VoiceSearchFactory({MicrophoneRecorder? Function()? recorderForPlatform})
    : _recorderForPlatform = recorderForPlatform ?? _defaultRecorder;

  static MicrophoneRecorder? _defaultRecorder() => Platform.isLinux ? PulseMicrophoneRecorder() : null;

  /// The server address the user configured, or empty.
  static String configuredUrl(SettingsService settings) => settings.read(SettingsService.voiceSearchUrl).trim();

  Future<VoiceSearchController?> create(SettingsService settings) async {
    final url = configuredUrl(settings);
    final recorder = _recorderForPlatform();
    if (url.isEmpty || recorder == null || !await recorder.isAvailable()) return null;
    final language = settings.read(SettingsService.voiceSearchLanguage).trim();
    return VoiceSearchController(
      recorder: recorder,
      transcriber: WhisperHttpTranscriber(url: url, model: settings.read(SettingsService.voiceSearchModel)),
      language: language.isEmpty ? null : language,
    );
  }
}
