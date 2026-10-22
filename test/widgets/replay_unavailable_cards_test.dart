import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/focus/card_focus_scope.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/replay/mapping/replay_mapper.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/focusable_media_card.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/widgets/replay/replay_unavailable_overlay.dart';
import 'package:plezy/widgets/replay_channel_logo.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

MediaItem _replay(
  ReplayAvailability availability, {
  String id = 'nologo:a',
  MediaKind kind = MediaKind.movie,
  String? libraryTitle,
  String? serverName,
  String? studio,
  int? durationMs,
}) {
  return testMediaItem(
    id: id,
    backend: MediaBackend.replay,
    kind: kind,
    title: 'Des racines et des ailes',
    summary: 'Un documentaire.',
    studio: studio,
    durationMs: durationMs,
    libraryTitle: libraryTitle,
    serverName: serverName,
    raw: {replayAvailabilityKey: availability.name},
  );
}

Widget _app(Widget child) => InputModeTracker(
  child: MaterialApp(
    theme: monoTheme(MonoPalette.dark),
    home: Scaffold(body: Center(child: child)),
  ),
);

Widget _stack(MediaItem item, {required bool focused, bool compact = false}) => _app(
  SizedBox(
    width: 189,
    height: 282,
    child: CardFocusScope(
      showFocus: focused,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ReplayUnavailableShade(
            item: item,
            child: const ColoredBox(color: Colors.blue),
          ),
          ReplayUnavailablePlate(item: item, compact: compact),
        ],
      ),
    ),
  ),
);

Size _plateSize(WidgetTester tester) =>
    tester.getSize(find.descendant(of: find.byType(ReplayUnavailablePlate), matching: find.byType(DecoratedBox)).first);

ColorFilter _filterOf(WidgetTester tester) => tester.widget<ColorFiltered>(find.byType(ColorFiltered)).colorFilter;

Widget _card(MediaItem item, {FocusNode? focusNode, bool showChannelLogo = false}) => _app(
  SizedBox(
    width: 189,
    height: 330,
    child: FocusableMediaCard(
      item: item,
      focusNode: focusNode,
      isOffline: true,
      disableScale: true,
      showChannelLogo: showChannelLogo,
      onTap: () {},
    ),
  ),
);

Widget _row(MediaItem item, {String? libraryName}) => _app(
  SizedBox(
    width: 420,
    child: MediaCard(
      item: item,
      viewModeOverride: ViewMode.list,
      showServerName: true,
      libraryName: libraryName,
      isOffline: true,
      onTap: () {},
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
  });

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  group('artwork and plate', () {
    testWidgets('a resting card is greyed and carries a 48 px plate', (tester) async {
      await tester.pumpWidget(_stack(_replay(ReplayAvailability.drmProtected), focused: false));
      await tester.pumpAndSettle();

      expect(_filterOf(tester), ColorFilter.matrix(replayGreyMatrix(ReplayUnavailableShade.restBrightness)));
      expect(_plateSize(tester), const Size(48, 48));
      expect(find.text('Protected by DRM'), findsNothing);
    });

    testWidgets('a focused card is lighter and its plate states the reason', (tester) async {
      await tester.pumpWidget(_stack(_replay(ReplayAvailability.drmProtected), focused: false));
      await tester.pumpWidget(_stack(_replay(ReplayAvailability.drmProtected), focused: true));
      await tester.pumpAndSettle();

      expect(_filterOf(tester), ColorFilter.matrix(replayGreyMatrix(ReplayUnavailableShade.focusBrightness)));
      expect(find.text('Protected by DRM'), findsOneWidget);
      expect(_plateSize(tester).width, 189 - 24);
    });

    testWidgets('the list row plate stays 36 px at focus', (tester) async {
      await tester.pumpWidget(_stack(_replay(ReplayAvailability.loginRequired), focused: true, compact: true));
      await tester.pumpAndSettle();

      expect(_plateSize(tester), const Size(36, 36));
      expect(find.text('Account required'), findsNothing);
    });

    testWidgets('a playable title is left alone', (tester) async {
      await tester.pumpWidget(_stack(_replay(ReplayAvailability.playable), focused: true));
      await tester.pumpAndSettle();

      expect(find.byType(ColorFiltered), findsNothing);
      expect(
        find.descendant(of: find.byType(ReplayUnavailablePlate), matching: find.byType(DecoratedBox)),
        findsNothing,
      );
    });
  });

  group('in a card', () {
    testWidgets('an unavailable card keeps focus and names the reason', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_card(_replay(ReplayAvailability.upcoming), focusNode: node));
      await tester.pumpAndSettle();
      expect(find.text('Not available yet'), findsNothing);

      node.requestFocus();
      await tester.pumpAndSettle();

      expect(node.hasFocus, isTrue);
      expect(find.text('Not available yet'), findsOneWidget);
    });

    testWidgets('the screen reader hears the reason with the card', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_card(_replay(ReplayAvailability.expired)));

      expect(find.bySemanticsLabel(RegExp(r'Des racines et des ailes.*Expired')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the logo plate sits 8 px from the corner when asked for', (tester) async {
      await tester.pumpWidget(_card(_replay(ReplayAvailability.playable), showChannelLogo: true));

      expect(find.byType(ReplayChannelLogo), findsOneWidget);
      final slot = tester.widget<Positioned>(
        find.ancestor(of: find.byType(ReplayChannelLogo), matching: find.byType(Positioned)).first,
      );
      expect(slot.left, 8);
      expect(slot.top, 8);
    });

    testWidgets('the logo plate does not move when the card takes focus', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_card(_replay(ReplayAvailability.playable), focusNode: node, showChannelLogo: true));
      final before = tester.getTopLeft(find.byType(ReplayChannelLogo));

      node.requestFocus();
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byType(ReplayChannelLogo)), before);
    });

    testWidgets('no logo plate by default or on a media server card', (tester) async {
      await tester.pumpWidget(_card(_replay(ReplayAvailability.playable)));
      expect(find.byType(ReplayChannelLogo), findsNothing);

      await tester.pumpWidget(_card(testMediaItem(id: 'x', title: 'Film'), showChannelLogo: true));
      expect(find.byType(ReplayChannelLogo), findsNothing);
    });
  });

  group('in a list row', () {
    testWidgets('the reason is written under the origin line at rest', (tester) async {
      await tester.pumpWidget(
        _row(
          _replay(ReplayAvailability.geoBlocked, libraryTitle: 'nologo', serverName: 'Catch-up TV'),
          libraryName: 'nologo',
        ),
      );

      expect(find.text('Not available in your country'), findsOneWidget);
    });

    testWidgets('the origin line names the channel once and the second line drops it', (tester) async {
      final item = _replay(
        ReplayAvailability.playable,
        libraryTitle: 'nologo',
        serverName: 'Catch-up TV',
        studio: 'nologo',
        durationMs: 7 * 60000,
      );
      await tester.pumpWidget(_row(item, libraryName: 'nologo'));
      await tester.pump();

      expect(find.text('Catch-up TV'), findsOneWidget);
      expect(find.text('•'), findsOneWidget);
      expect(find.byType(ReplayChannelLogo), findsOneWidget);
      expect(find.textContaining('nologo'), findsOneWidget);
    });

    testWidgets('a media server row keeps its studio on the second line', (tester) async {
      final item = testMediaItem(id: 'p', title: 'Film', studio: 'Studio X', serverName: 'Plex', durationMs: 60000);
      await tester.pumpWidget(_row(item, libraryName: 'Movies'));

      expect(find.textContaining('Studio X'), findsOneWidget);
      expect(find.byType(ReplayChannelLogo), findsNothing);
    });

    testWidgets('a catch-up row without a library label keeps the channel in the second line', (tester) async {
      final item = _replay(ReplayAvailability.playable, serverName: 'Catch-up TV', studio: 'nologo');
      await tester.pumpWidget(_row(item));

      expect(find.textContaining('nologo'), findsOneWidget);
    });
  });
}
