import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/voice/voice_transcriber.dart';
import 'package:plezy/voice/whisper_http_transcriber.dart';

final _wav = Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0]);

void main() {
  group('WhisperHttpTranscriber', () {
    test('a bare server address gets the standard transcription path', () {
      expect(WhisperHttpTranscriber(url: 'http://host:8178').endpoint.path, '/v1/audio/transcriptions');
      expect(WhisperHttpTranscriber(url: 'http://host:8178/').endpoint.path, '/v1/audio/transcriptions');
      expect(WhisperHttpTranscriber(url: 'http://host/inference').endpoint.path, '/inference');
    });

    test('posts the recording with model and language and returns the text', () async {
      late http.BaseRequest seen;
      late String body;
      final client = MockClient.streaming((request, stream) async {
        seen = request;
        body = utf8.decode(await stream.toBytes(), allowMalformed: true);
        return http.StreamedResponse(Stream.value(utf8.encode('{"text": " les gardiens de l eau "}')), 200);
      });
      final text = await WhisperHttpTranscriber(
        url: 'http://host:8178',
        model: 'small',
        client: client,
      ).transcribe(_wav, language: 'fr');

      expect(text, 'les gardiens de l eau');
      expect(seen.method, 'POST');
      expect(body, contains('name="model"'));
      expect(body, contains('small'));
      expect(body, contains('name="language"'));
      expect(body, contains('name="file"'));
    });

    test('an empty language is left out so the server detects it', () async {
      late String body;
      final client = MockClient.streaming((request, stream) async {
        body = utf8.decode(await stream.toBytes(), allowMalformed: true);
        return http.StreamedResponse(Stream.value(utf8.encode('{"text":"x"}')), 200);
      });
      await WhisperHttpTranscriber(url: 'http://host', client: client).transcribe(_wav, language: '');
      expect(body, isNot(contains('name="language"')));
    });

    test('a server that answers plain text is accepted', () async {
      final client = MockClient((_) async => http.Response('hello there\n', 200));
      expect(await WhisperHttpTranscriber(url: 'http://host', client: client).transcribe(_wav), 'hello there');
    });

    test('an HTTP error is reported with its status', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => WhisperHttpTranscriber(url: 'http://host', client: client).transcribe(_wav),
        throwsA(isA<VoiceTranscriptionException>().having((e) => e.message, 'message', contains('503'))),
      );
    });

    test('an unreachable server is reported without a stack trace', () async {
      final client = MockClient((_) async => throw http.ClientException('connection refused'));
      expect(
        () => WhisperHttpTranscriber(url: 'http://host', client: client).transcribe(_wav),
        throwsA(isA<VoiceTranscriptionException>().having((e) => e.message, 'message', contains('refused'))),
      );
    });

    test('a JSON answer without text is rejected', () async {
      final client = MockClient((_) async => http.Response('{"segments": []}', 200));
      expect(
        () => WhisperHttpTranscriber(url: 'http://host', client: client).transcribe(_wav),
        throwsA(isA<VoiceTranscriptionException>()),
      );
    });
  });
}
