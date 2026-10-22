import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/screens/replay/replay_detail_hooks.dart';
import 'package:plezy/screens/replay/replay_detail_info_line.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/replay_channel_logo.dart';

import '../../test_helpers/media_items.dart';
import 'replay_detail_fixtures.dart';

const _style = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white);

Widget _host(Widget child) => MaterialApp(
  theme: monoTheme(MonoPalette.dark),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('information line', () {
    testWidgets('a channel with a bundled logo shows the logo, then a bullet and the fields', (tester) async {
      final item = replayItem('arte:1', ReplayAvailability.playable, studio: 'ARTE');
      await tester.pumpWidget(_host(ReplayDetailInfoLine(item: item, textStyle: _style, rest: const Text('S1 E94'))));
      await tester.pumpAndSettle();

      expect(find.byType(ReplayChannelLogo), findsOneWidget);
      expect(find.text('ARTE'), findsNothing);
      expect(find.text('S1 E94'), findsOneWidget);
      expect(find.textContaining('•'), findsOneWidget);
    });

    testWidgets('a channel without a logo shows its whole name in the style of the line', (tester) async {
      final item = replayItem('nologo:1', ReplayAvailability.playable, studio: 'Télésambre');
      await tester.pumpWidget(_host(ReplayDetailInfoLine(item: item, textStyle: _style, rest: const Text('2026'))));
      await tester.pumpAndSettle();

      final name = tester.widget<Text>(find.text('Télésambre'));
      expect(name.style?.fontSize, 18);
      expect(name.style?.fontWeight, FontWeight.w700);
      expect(find.byType(ReplayChannelLogo), findsNothing);
    });

    testWidgets('a channel with no other field has no bullet', (tester) async {
      final item = replayItem('arte:1', ReplayAvailability.playable, studio: 'ARTE');
      await tester.pumpWidget(_host(ReplayDetailInfoLine(item: item, textStyle: _style)));
      await tester.pumpAndSettle();

      expect(find.textContaining('•'), findsNothing);
    });

    testWidgets('a title of another backend keeps its fields untouched', (tester) async {
      final plex = testMediaItem(id: 'plex-1');
      await tester.pumpWidget(_host(replayInfoLine(plex, _style, const Text('2026'))));

      expect(find.text('2026'), findsOneWidget);
      expect(find.byType(ReplayDetailInfoLine), findsNothing);
    });
  });

  group('artwork tint', () {
    testWidgets('the artwork of a blocked title is greyed and dimmed', (tester) async {
      final page = replayItem('francetv:s', ReplayAvailability.geoBlocked, kind: MediaKind.show);
      await tester.pumpWidget(_host(replayTinted(page, const [], const SizedBox(width: 10, height: 10))));

      expect(find.byType(ColorFiltered), findsOneWidget);
    });

    testWidgets('a playable title is left alone', (tester) async {
      final page = replayItem('francetv:s', ReplayAvailability.playable, kind: MediaKind.show);
      await tester.pumpWidget(_host(replayTinted(page, const [], const SizedBox(width: 10, height: 10))));

      expect(find.byType(ColorFiltered), findsNothing);
    });

    testWidgets('a show whose episodes are all blocked is greyed', (tester) async {
      final page = replayItem('francetv:s', ReplayAvailability.playable, kind: MediaKind.show);
      final blocked = replayItem('francetv:e', ReplayAvailability.geoBlocked);
      await tester.pumpWidget(_host(replayTinted(page, [blocked], const SizedBox(width: 10, height: 10))));

      expect(find.byType(ColorFiltered), findsOneWidget);
    });

    testWidgets('a logo that is only text keeps its ink', (tester) async {
      final page = replayItem('francetv:s', ReplayAvailability.geoBlocked, kind: MediaKind.show);
      await tester.pumpWidget(_host(replayTintedLogo(page, const [], const Text('Titre'))));

      expect(find.byType(ColorFiltered), findsNothing);
    });

    testWidgets('a logo image is greyed with the artwork', (tester) async {
      final page = replayItem(
        'francetv:s',
        ReplayAvailability.geoBlocked,
        kind: MediaKind.show,
        clearLogoPath: 'https://img.test/logo.png',
      );
      await tester.pumpWidget(_host(replayTintedLogo(page, const [], const SizedBox(width: 10, height: 10))));

      expect(find.byType(ColorFiltered), findsOneWidget);
    });
  });

  group('initial focus', () {
    final show = replayItem('francetv:s', ReplayAvailability.playable, kind: MediaKind.show);
    final blocked = replayItem('francetv:e1', ReplayAvailability.geoBlocked);
    final playable = replayItem('francetv:e2', ReplayAvailability.playable);

    Future<BuildContext> contextOf(WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      return captured;
    }

    testWidgets('a catch-up show opens on its first playable episode', (tester) async {
      final context = await contextOf(tester);
      expect(replayInitialEpisodeId(context, show, null, [blocked, playable]), playable.id);
    });

    testWidgets('a playable on-deck episode wins', (tester) async {
      final context = await contextOf(tester);
      final onDeck = replayItem('francetv:e3', ReplayAvailability.playable);
      expect(replayInitialEpisodeId(context, show, onDeck, [blocked, playable]), onDeck.id);
    });

    testWidgets('a show of another backend keeps the on-deck episode', (tester) async {
      final context = await contextOf(tester);
      final plexShow = testMediaItem(id: 'plex-s', kind: MediaKind.show);
      final onDeck = testMediaItem(id: 'plex-e', kind: MediaKind.episode);
      expect(replayInitialEpisodeId(context, plexShow, onDeck, [onDeck]), onDeck.id);
    });

    testWidgets('the action row takes the focus when no episode plays', (tester) async {
      final context = await contextOf(tester);
      expect(replayActionRowTakesFocus(context, show, [blocked]), isTrue);
      expect(replayActionRowTakesFocus(context, show, [blocked, playable]), isFalse);
    });
  });
}
