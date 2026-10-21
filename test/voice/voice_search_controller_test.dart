import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/voice/microphone_recorder.dart';
import 'package:plezy/voice/voice_search_controller.dart';
import 'package:plezy/voice/voice_transcriber.dart';

class _FakeRecorder implements MicrophoneRecorder {
  bool recording = false;
  bool failToStart = false;
  int cancels = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start() async {
    if (failToStart) throw const MicrophoneException('The microphone could not be opened');
    recording = true;
  }

  @override
  Future<Uint8List> stop() async {
    recording = false;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> cancel() async {
    recording = false;
    cancels++;
  }
}

class _FakeTranscriber implements VoiceTranscriber {
  String answer = 'dix pour cent';
  Object? failure;
  String? lastLanguage;

  @override
  Future<String> transcribe(Uint8List wav, {String? language}) async {
    lastLanguage = language;
    if (failure != null) throw failure!;
    return answer;
  }
}

void main() {
  late _FakeRecorder recorder;
  late _FakeTranscriber transcriber;
  late VoiceSearchController controller;

  setUp(() {
    recorder = _FakeRecorder();
    transcriber = _FakeTranscriber();
    controller = VoiceSearchController(recorder: recorder, transcriber: transcriber, language: 'fr');
  });

  tearDown(() => controller.dispose());

  test('the first tap listens and the second returns the transcript', () async {
    expect(await controller.toggle(), isNull);
    expect(controller.state, VoiceSearchState.listening);
    expect(recorder.recording, isTrue);

    expect(await controller.toggle(), 'dix pour cent');
    expect(controller.state, VoiceSearchState.idle);
    expect(transcriber.lastLanguage, 'fr');
  });

  test('a microphone that cannot open leaves the controller idle with a message', () async {
    recorder.failToStart = true;
    await controller.toggle();
    expect(controller.state, VoiceSearchState.idle);
    expect(controller.error, contains('microphone'));
  });

  test('a transcription failure is kept as the error and gives no text', () async {
    transcriber.failure = const VoiceTranscriptionException('The transcription server answered HTTP 500');
    await controller.toggle();
    expect(await controller.toggle(), isNull);
    expect(controller.error, contains('500'));
    expect(controller.state, VoiceSearchState.idle);
  });

  test('silence gives no text and no error', () async {
    transcriber.answer = '';
    await controller.toggle();
    expect(await controller.toggle(), isNull);
    expect(controller.error, isNull);
  });

  test('cancelling stops the recording and clears the state', () async {
    await controller.toggle();
    await controller.cancel();
    expect(controller.state, VoiceSearchState.idle);
    expect(recorder.cancels, 1);
  });

  test('the error of a failed attempt is cleared by the next one', () async {
    recorder.failToStart = true;
    await controller.toggle();
    recorder.failToStart = false;
    await controller.toggle();
    expect(controller.error, isNull);
  });
}
