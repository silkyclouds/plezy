import 'package:flutter/foundation.dart';

import 'microphone_recorder.dart';
import 'voice_transcriber.dart';

enum VoiceSearchState { idle, listening, transcribing }

/// Drives one voice search: first tap starts recording, second tap stops it and transcribes.
class VoiceSearchController extends ChangeNotifier {
  final MicrophoneRecorder _recorder;
  final VoiceTranscriber _transcriber;
  final String? language;
  final Duration maxDuration;

  VoiceSearchState _state = VoiceSearchState.idle;
  String? _error;
  DateTime? _startedAt;
  bool _disposed = false;

  VoiceSearchController({
    required this._recorder,
    required this._transcriber,
    this.language,
    this.maxDuration = const Duration(seconds: 12),
  });

  VoiceSearchState get state => _state;

  /// Why the last attempt gave nothing, or null.
  String? get error => _error;

  /// Starts listening, or stops and returns the transcript. Returns null when nothing was recognised
  /// and whenever this call only started recording.
  Future<String?> toggle() async {
    switch (_state) {
      case VoiceSearchState.idle:
        await _begin();
        return null;
      case VoiceSearchState.listening:
        return _finish();
      case VoiceSearchState.transcribing:
        return null;
    }
  }

  /// Stops a recording in progress and discards it.
  Future<void> cancel() async {
    if (_state == VoiceSearchState.listening) await _recorder.cancel();
    _set(VoiceSearchState.idle);
  }

  /// True once the recording has run for [maxDuration], so the caller can finish it.
  bool get reachedLimit => _startedAt != null && DateTime.now().difference(_startedAt!) >= maxDuration;

  Future<void> _begin() async {
    _error = null;
    try {
      await _recorder.start();
    } on MicrophoneException catch (e) {
      _error = e.message;
      _set(VoiceSearchState.idle);
      return;
    }
    _startedAt = DateTime.now();
    _set(VoiceSearchState.listening);
  }

  Future<String?> _finish() async {
    _set(VoiceSearchState.transcribing);
    try {
      final wav = await _recorder.stop();
      final text = await _transcriber.transcribe(wav, language: language);
      return text.isEmpty ? null : text;
    } on MicrophoneException catch (e) {
      _error = e.message;
    } on VoiceTranscriptionException catch (e) {
      _error = e.message;
    } finally {
      _startedAt = null;
      _set(VoiceSearchState.idle);
    }
    return null;
  }

  void _set(VoiceSearchState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_state == VoiceSearchState.listening) _recorder.cancel();
    super.dispose();
  }
}
