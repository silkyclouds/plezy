import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'voice_transcriber.dart';

/// Transcribes through a server that speaks the OpenAI `audio/transcriptions` API, such as
/// whisper.cpp's server, faster-whisper-server or LocalAI.
class WhisperHttpTranscriber implements VoiceTranscriber {
  static const _defaultPath = '/v1/audio/transcriptions';

  final Uri endpoint;
  final String model;
  final http.Client _client;
  final Duration timeout;

  /// [url] may be a bare server address; the standard path is added when it has none.
  WhisperHttpTranscriber({
    required String url,
    this.model = 'whisper-1',
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : endpoint = _endpointFor(url),
       _client = client ?? http.Client();

  static Uri _endpointFor(String url) {
    final uri = Uri.parse(url.trim());
    final hasPath = uri.path.isNotEmpty && uri.path != '/';
    return hasPath ? uri : uri.replace(path: _defaultPath);
  }

  @override
  Future<String> transcribe(Uint8List wav, {String? language}) async {
    final request = http.MultipartRequest('POST', endpoint)
      ..fields['model'] = model
      ..fields['response_format'] = 'json'
      ..files.add(http.MultipartFile.fromBytes('file', wav, filename: 'speech.wav'));
    if (language != null && language.isNotEmpty) request.fields['language'] = language;

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw const VoiceTranscriptionException('The transcription server did not answer in time');
    } on http.ClientException catch (e) {
      throw VoiceTranscriptionException('Could not reach the transcription server: ${e.message}');
    }
    if (response.statusCode != 200) {
      throw VoiceTranscriptionException('The transcription server answered HTTP ${response.statusCode}');
    }
    return _textOf(response.body);
  }

  String _textOf(String body) {
    try {
      final json = jsonDecode(body);
      final text = json is Map<String, dynamic> ? json['text'] : null;
      if (text is String) return text.trim();
    } on FormatException {
      // Plain-text servers answer with the transcript itself.
      return body.trim();
    }
    throw const VoiceTranscriptionException('The transcription server sent an answer without text');
  }
}
