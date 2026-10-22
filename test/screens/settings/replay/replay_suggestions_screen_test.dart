import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/provider/replay_source_info.dart';
import 'package:plezy/replay/suggestions/replay_suggestion_events.dart';
import 'package:plezy/replay/suggestions/replay_suggestion_settings.dart';
import 'package:plezy/replay/suggestions/replay_suggestion_store.dart';
import 'package:plezy/screens/settings/replay/replay_suggestions_screen.dart';
import 'package:plezy/theme/mono_theme.dart';

ReplaySourceInfo _channel(String id, String name, List<String> languages) =>
    ReplaySourceInfo(id: id, name: name, support: ReplayPlaybackSupport.clear, country: 'FR', languages: languages);

final _channels = [
  _channel('lrt', 'LRT', ['lt']),
  _channel('arte', 'ARTE', ['fr']),
  _channel('auvio', 'Auvio', ['fr', 'nl']),
];

Future<ReplaySuggestionStore> _pump(WidgetTester tester, {ReplaySuggestionSettings? initial}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = ReplaySuggestionStore(null, ServerId('replay'));
  if (initial != null) await store.save(initial);
  await tester.pumpWidget(
    InputModeTracker(
      child: MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: ReplaySuggestionsScreen(
          store: store,
          automaticLanguages: () async => {'fr'},
          rowChoices: (id) async => [(id: 'docs', title: 'Documentaries'), (id: 'series', title: 'Series')],
          channels: _channels,
          locale: 'en',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('Channels are listed alphabetically with the reason they are on or off', (tester) async {
    await _pump(tester);

    final names = ['ARTE', 'Auvio', 'LRT'].map((n) => tester.getTopLeft(find.text(n).last).dy).toList();
    expect(names, orderedEquals([...names]..sort()));
    expect(find.text('On by rule: French followed'), findsNWidgets(2));
    expect(find.text('Off: Lithuanian not followed'), findsOneWidget);
  });

  testWidgets('Switching a channel against the rule saves the choice and offers the way back', (tester) async {
    final bumps = replaySuggestionsChanged.value;
    final store = await _pump(tester);

    await tester.tap(find.text('LRT'));
    await tester.pumpAndSettle();

    expect((await store.load()).channels, {'lrt': true});
    expect(find.text('On, your choice'), findsOneWidget);
    expect(replaySuggestionsChanged.value, greaterThan(bumps));

    await tester.tap(find.text('Back to the language rule'));
    await tester.pumpAndSettle();

    expect((await store.load()).channels, isEmpty);
    expect(find.text('Off: Lithuanian not followed'), findsOneWidget);
  });

  testWidgets('Ticking a language chip moves to a manual list with a way back', (tester) async {
    final store = await _pump(tester);
    expect(find.text('Back to automatic'), findsNothing);

    await tester.tap(find.text('Lithuanian'));
    await tester.pumpAndSettle();

    expect((await store.load()).languages, {'fr', 'lt'});
    expect(find.text('Chosen by hand'), findsOneWidget);

    await tester.tap(find.text('Back to automatic'));
    await tester.pumpAndSettle();

    expect((await store.load()).languages, isEmpty);
  });

  testWidgets('With the master switch off the channel rows do nothing', (tester) async {
    final store = await _pump(tester, initial: const ReplaySuggestionSettings(enabled: false));

    await tester.tap(find.text('LRT'));
    await tester.pumpAndSettle();

    expect((await store.load()).channels, isEmpty);
  });

  testWidgets('Rows per channel opens a menu of 1 to 4 and saves the choice', (tester) async {
    final store = await _pump(tester);

    await tester.tap(find.text('Rows per channel'));
    await tester.pumpAndSettle();
    expect([for (var n = 1; n <= 4; n++) find.text('$n').evaluate().isNotEmpty], everyElement(isTrue));

    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();

    expect((await store.load()).rowsPerChannel, 3);
  });

  testWidgets('The rows dialog mutes an unticked row and cannot be saved with no row ticked', (tester) async {
    final store = await _pump(tester);

    await tester.tap(find.text('Rows: all').first);
    await tester.pumpAndSettle();
    expect(find.text('Rows of ARTE'), findsOneWidget);

    await tester.tap(find.text('Series'));
    await tester.pump();
    await tester.tap(find.text('Documentaries'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Rows of ARTE'), findsOneWidget);

    await tester.tap(find.text('Documentaries'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await store.load()).mutedRows, {'arte:series'});
    expect(find.text('Rows: all except Series'), findsOneWidget);
  });
}
