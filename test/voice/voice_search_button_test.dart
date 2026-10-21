import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/voice/microphone_recorder.dart';
import 'package:plezy/voice/voice_search_factory.dart';
import 'package:plezy/widgets/voice_search_button.dart';

import '../test_helpers/prefs.dart';

class _Recorder implements MicrophoneRecorder {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<Uint8List> stop() async => Uint8List(4);

  @override
  Future<void> cancel() async {}
}

Widget _host(VoiceSearchButton button) => TranslationProvider(
  child: MaterialApp(
    home: Scaffold(body: Center(child: button)),
  ),
);

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
  });

  testWidgets('the button stays hidden until a server address is set', (tester) async {
    var available = false;
    await tester.pumpWidget(
      _host(
        VoiceSearchButton(
          onTranscript: (_) {},
          onAvailabilityChanged: (v) => available = v,
          factory: VoiceSearchFactory(recorderForPlatform: _Recorder.new),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IconButton), findsNothing);
    expect(available, isFalse);
  });

  testWidgets('the button appears once a server address is set', (tester) async {
    await SettingsService.instance.write(SettingsService.voiceSearchUrl, 'http://host:8178');
    var available = false;
    await tester.pumpWidget(
      _host(
        VoiceSearchButton(
          onTranscript: (_) {},
          onAvailabilityChanged: (v) => available = v,
          factory: VoiceSearchFactory(recorderForPlatform: _Recorder.new),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IconButton), findsOneWidget);
    expect(available, isTrue);
  });

  testWidgets('a platform without a recorder never shows the button', (tester) async {
    await SettingsService.instance.write(SettingsService.voiceSearchUrl, 'http://host:8178');
    await tester.pumpWidget(
      _host(
        VoiceSearchButton(
          onTranscript: (_) {},
          factory: VoiceSearchFactory(recorderForPlatform: () => null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IconButton), findsNothing);
  });
}
