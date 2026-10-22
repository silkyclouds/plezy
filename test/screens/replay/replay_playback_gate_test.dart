import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/screens/replay/replay_playback_gate.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../../test_helpers/media_items.dart';
import 'replay_detail_fixtures.dart';

/// Asks the gate about [item] from a button and records its answer.
Future<ValueNotifier<bool?>> _ask(WidgetTester tester, MediaItem item) async {
  final answer = ValueNotifier<bool?>(null);
  await tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(MonoPalette.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer.value = await replayAllowsPlayback(context, item),
            child: const Text('play'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('play'));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets('a playable title starts at once, without a dialog', (tester) async {
    final answer = await _ask(tester, replayItem('arte:1', ReplayAvailability.playable));

    expect(answer.value, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('a title of another backend starts at once', (tester) async {
    final answer = await _ask(tester, testMediaItem(id: 'plex-1'));

    expect(answer.value, isTrue);
  });

  testWidgets('a geo-blocked title shows the dialog instead of starting', (tester) async {
    final answer = await _ask(tester, replayItem('francetv:1', ReplayAvailability.geoBlocked, studio: 'France.tv'));

    expect(find.byType(Dialog), findsOneWidget);
    expect(answer.value, isNull, reason: 'still waiting for the viewer');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answer.value, isFalse);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('Escape on the dialog does not start playback', (tester) async {
    final answer = await _ask(tester, replayItem('arte:1', ReplayAvailability.expired, studio: 'ARTE'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(answer.value, isFalse);
  });
}
