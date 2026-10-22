import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/provider/replay_source_groups.dart';
import 'package:plezy/replay/provider/replay_source_info.dart';
import 'package:plezy/screens/settings/replay/replay_channel_list.dart';
import 'package:plezy/theme/mono_theme.dart';

const _auvio = ReplaySourceInfo(
  id: 'auvio',
  name: 'Auvio',
  support: ReplayPlaybackSupport.partial,
  country: 'BE',
  languages: ['fr', 'nl'],
  supportsAccount: true,
);
const _vrt = ReplaySourceInfo(
  id: 'vrt',
  name: 'VRT Max',
  support: ReplayPlaybackSupport.clear,
  country: 'BE',
  languages: ['nl'],
);
const _arte = ReplaySourceInfo(
  id: 'arte',
  name: 'ARTE',
  support: ReplayPlaybackSupport.clear,
  country: 'FR',
  languages: ['fr'],
);
const _francetv = ReplaySourceInfo(
  id: 'francetv',
  name: 'France.tv',
  support: ReplayPlaybackSupport.partial,
  country: 'FR',
  languages: ['fr'],
  availableIn: {'FR'},
);

class _Harness extends StatefulWidget {
  final Set<String> enabled;
  final String? expanded;
  final String query;
  final List<(Set<String>, bool)> changes;

  const _Harness({required this.enabled, required this.expanded, this.query = '', required this.changes});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late String? _expanded = widget.expanded;
  late Set<String> _enabled = widget.enabled;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ReplayChannelList(
        groups: groupReplaySources([_auvio, _vrt, _arte, _francetv], viewerCountry: 'BE', locale: 'en'),
        enabled: _enabled,
        query: widget.query,
        locale: 'en',
        viewerCountry: 'BE',
        expandedCountry: _expanded,
        hasAccount: (info) => info.supportsAccount,
        isSignedIn: (info) => false,
        onToggleCountry: (code) => setState(() => _expanded = _expanded == code ? null : code),
        onSetEnabled: (ids, on) {
          widget.changes.add((ids, on));
          setState(() => _enabled = on ? {..._enabled, ...ids} : _enabled.difference(ids));
        },
        onAccount: (info, context) {},
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  Set<String> enabled = const {},
  String? expanded = 'BE',
  String query = '',
  List<(Set<String>, bool)>? changes,
}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    InputModeTracker(
      child: MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(
          body: _Harness(enabled: enabled, expanded: expanded, query: query, changes: changes ?? []),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _focused(WidgetTester tester, String text) => Focus.of(tester.element(find.text(text).first)).hasPrimaryFocus;

void main() {
  testWidgets('Only the open country shows its channels', (tester) async {
    await _pump(tester);

    expect(find.text('Auvio'), findsOneWidget);
    expect(find.text('ARTE'), findsNothing);
  });

  testWidgets('A header counts the channels on and the ones that do not play from the viewer country', (tester) async {
    await _pump(tester, enabled: {'auvio'});

    expect(find.text('1 of 2 on'), findsOneWidget);
    expect(find.text('0 of 2 on · 1 does not play from Belgium'), findsOneWidget);
  });

  testWidgets('Opening a country closes the other one', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('France'));
    await tester.pumpAndSettle();

    expect(find.text('ARTE'), findsOneWidget);
    expect(find.text('Auvio'), findsNothing);
  });

  testWidgets('A channel that does not play from the viewer country carries a warning', (tester) async {
    await _pump(tester, expanded: 'FR');

    expect(find.text('Does not play from Belgium'), findsOneWidget);
  });

  testWidgets('Right opens a closed header and Left closes it, focus staying put', (tester) async {
    await _pump(tester, expanded: null);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.text('Auvio'), findsOneWidget);
    expect(_focused(tester, 'Belgium'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.text('Auvio'), findsNothing);
    expect(_focused(tester, 'Belgium'), isTrue);
  });

  testWidgets('Left on a channel row goes back to the country header', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focused(tester, 'Belgium'), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(_focused(tester, 'Belgium'), isTrue);
  });

  testWidgets('Select on a channel row switches it', (tester) async {
    final changes = <(Set<String>, bool)>[];
    await _pump(tester, changes: changes);

    await tester.tap(find.text('Auvio'));
    await tester.pump();

    expect(changes.single.$1, {'auvio'});
    expect(changes.single.$2, isTrue);
  });

  testWidgets('All channels switches the whole country, on only when every channel is on', (tester) async {
    final changes = <(Set<String>, bool)>[];
    await _pump(tester, enabled: {'auvio'}, changes: changes);

    await tester.tap(find.text('All channels in Belgium'));
    await tester.pump();

    expect(changes.single.$1, {'auvio', 'vrt'});
    expect(changes.single.$2, isTrue);
  });

  testWidgets('The sign-in row follows the channel switch', (tester) async {
    await _pump(tester, enabled: {'auvio'});
    expect(find.text('Sign in to Auvio'), findsOneWidget);

    await tester.tap(find.text('Auvio'));
    await tester.pump();

    expect(find.text('Sign in to Auvio'), findsNothing);
  });

  testWidgets('Language groups label a country with several languages', (tester) async {
    await _pump(tester);

    expect(find.text('French'), findsOneWidget);
    expect(find.text('Dutch'), findsOneWidget);
    expect(find.text('Plays some titles · French, Dutch'), findsOneWidget);
  });

  testWidgets('A search lists the channels found, drawers open, language groups hidden', (tester) async {
    await _pump(tester, expanded: 'FR', query: 'au');

    expect(find.text('Auvio'), findsOneWidget);
    expect(find.text('ARTE'), findsNothing);
    expect(find.text('French'), findsNothing);
    expect(find.text('All channels in Belgium'), findsNothing);
  });

  testWidgets('A search without result says so', (tester) async {
    await _pump(tester, query: 'xyz');

    expect(find.text('No channel for “xyz”'), findsOneWidget);
  });
}
