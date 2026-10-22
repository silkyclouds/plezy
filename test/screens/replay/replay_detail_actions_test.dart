import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/focus/focusable_action_bar.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/screens/replay/replay_detail_actions.dart';
import 'package:plezy/screens/replay/replay_unavailable_texts.dart';
import 'package:plezy/theme/mono_theme.dart';

import 'replay_detail_fixtures.dart';

FocusableAction _icon(String label, {required Key key}) => FocusableAction(
  debugLabel: label,
  onPressed: () {},
  builder: (context, state) => SizedBox(key: key, width: 48, height: 48),
);

ReplayActionRowSpec _spec(MediaItem page, FocusNode primary, {VoidCallback? onSignedIn}) => ReplayActionRowSpec(
  page: page,
  episodes: const [],
  primaryFocusNode: primary,
  actionSize: 48,
  tvScale: 1,
  isTv: false,
  watched: _icon('detail_watched', key: const Key('watched')),
  more: _icon('detail_more', key: const Key('more')),
  onSignedIn: onSignedIn ?? () {},
);

Future<void> _pump(WidgetTester tester, List<FocusableAction> actions) => tester.pumpWidget(
  MaterialApp(
    theme: monoTheme(MonoPalette.dark),
    home: Scaffold(body: FocusableActionBar(actions: actions, spacing: 8)),
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  late FocusNode primary;
  setUp(() => primary = FocusNode());
  tearDown(() => primary.dispose());

  ReplayUnavailableTexts texts(ReplayAvailability availability) => ReplayUnavailableTexts(
    availability: availability,
    icon: Symbols.public_off_rounded,
    notice: 'Only in France. Plezy places you in Belgium.',
    dialogTitle: 'Title',
    dialogBody: 'Body',
  );

  testWidgets('the notice replaces Play and keeps Watched and the menu after it', (tester) async {
    final page = replayItem('francetv:1', ReplayAvailability.geoBlocked);
    final actions = replayActionRow(_spec(page, primary), texts(ReplayAvailability.geoBlocked));
    await _pump(tester, actions);

    expect(find.text('Only in France. Plezy places you in Belgium.'), findsOneWidget);
    expect(actions.map((a) => a.debugLabel), ['detail_replay_notice', 'detail_watched', 'detail_more']);
    expect(find.byKey(const Key('watched')), findsOneWidget);
    expect(find.byKey(const Key('more')), findsOneWidget);
  });

  testWidgets('the notice cannot take focus', (tester) async {
    final page = replayItem('francetv:1', ReplayAvailability.geoBlocked);
    final actions = replayActionRow(_spec(page, primary), texts(ReplayAvailability.geoBlocked));

    expect(actions.first.onPressed, isNull);
  });

  testWidgets('the primary focus node lands on the menu', (tester) async {
    final page = replayItem('francetv:1', ReplayAvailability.geoBlocked);
    await _pump(tester, replayActionRow(_spec(page, primary), texts(ReplayAvailability.geoBlocked)));

    primary.requestFocus();
    await tester.pump();

    expect(primary.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(primary.hasFocus, isTrue, reason: 'the menu is the last action');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(primary.hasFocus, isFalse, reason: 'Left reaches Watched, skipping the notice');
  });

  testWidgets('the notice sits 28 before Watched', (tester) async {
    final page = replayItem('francetv:1', ReplayAvailability.geoBlocked);
    final actions = replayActionRow(_spec(page, primary), texts(ReplayAvailability.geoBlocked));
    await _pump(tester, actions);

    final notice = tester.getRect(find.text('Only in France. Plezy places you in Belgium.'));
    final watched = tester.getRect(find.byKey(const Key('watched')));
    expect(watched.left - notice.right, greaterThanOrEqualTo(28));
  });

  testWidgets('a sign-in offer puts a focusable button in Play\'s place', (tester) async {
    final page = replayItem('rtlplay:1', ReplayAvailability.loginRequired);
    var asked = 0;
    var signedIn = 0;
    final actions = replayActionRow(
      _spec(page, primary, onSignedIn: () => signedIn++),
      texts(ReplayAvailability.loginRequired),
      signIn: () async {
        asked++;
        return true;
      },
    );
    await _pump(tester, actions);

    expect(find.text(t.replay.signIn), findsOneWidget);
    expect(actions.first.focusNode, same(primary));
    primary.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(asked, 1);
    expect(signedIn, 1);
  });

  testWidgets('a failed sign-in leaves the page as it was', (tester) async {
    final page = replayItem('rtlplay:1', ReplayAvailability.loginRequired);
    var signedIn = 0;
    final actions = replayActionRow(
      _spec(page, primary, onSignedIn: () => signedIn++),
      texts(ReplayAvailability.loginRequired),
      signIn: () async => false,
    );
    await _pump(tester, actions);

    primary.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(signedIn, 0);
  });

  testWidgets('an account-only title with no way to sign in gets the notice', (tester) async {
    final page = replayItem('m6plus:1', ReplayAvailability.loginRequired);
    final actions = replayActionRow(_spec(page, primary), texts(ReplayAvailability.loginRequired));

    expect(actions.first.debugLabel, 'detail_replay_notice');
  });
}
