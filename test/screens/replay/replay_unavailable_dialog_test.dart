import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/screens/replay/replay_unavailable_dialog.dart';
import 'package:plezy/screens/replay/replay_unavailable_texts.dart';
import 'package:plezy/theme/mono_theme.dart';

ReplayUnavailableTexts _texts(ReplayAvailability availability) => ReplayUnavailableTexts(
  availability: availability,
  icon: Symbols.public_off_rounded,
  notice: 'notice',
  dialogTitle: 'Titre du dialogue',
  dialogBody: 'Texte du dialogue.',
);

/// Opens the dialog from a button and records what it returned.
Future<ValueNotifier<ReplayUnavailableChoice?>> _open(
  WidgetTester tester,
  ReplayUnavailableTexts texts, {
  bool canSignIn = false,
}) async {
  final result = ValueNotifier<ReplayUnavailableChoice?>(null);
  await tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(MonoPalette.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                result.value = await showReplayUnavailableDialog(context, texts, canSignIn: canSignIn),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets('a geo-blocked title offers to change the position, with Close focused', (tester) async {
    final result = await _open(tester, _texts(ReplayAvailability.geoBlocked));

    expect(find.text('Titre du dialogue'), findsOneWidget);
    expect(find.text('Texte du dialogue.'), findsOneWidget);
    expect(find.text(t.replay.detail.dialog.changeLocation), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result.value, ReplayUnavailableChoice.close);
  });

  testWidgets('Left moves from Close to the position button', (tester) async {
    final result = await _open(tester, _texts(ReplayAvailability.geoBlocked));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result.value, ReplayUnavailableChoice.changeLocation);
  });

  testWidgets('an account-only title puts Sign in on the right, focused', (tester) async {
    final result = await _open(tester, _texts(ReplayAvailability.loginRequired), canSignIn: true);

    final close = tester.getTopLeft(find.text(t.replay.detail.dialog.close));
    final signIn = tester.getTopLeft(find.text(t.replay.signIn));
    expect(signIn.dx, greaterThan(close.dx));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result.value, ReplayUnavailableChoice.signIn);
  });

  testWidgets('a title that cannot be signed in to offers only Close', (tester) async {
    await _open(tester, _texts(ReplayAvailability.loginRequired));

    expect(find.text(t.replay.signIn), findsNothing);
    expect(find.text(t.replay.detail.dialog.close), findsOneWidget);
  });

  testWidgets('the dialog is 640 wide on a large screen', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, _texts(ReplayAvailability.drmProtected));

    final card = find.descendant(of: find.byType(Dialog), matching: find.byType(SizedBox)).first;
    expect(tester.getSize(card).width, ReplayUnavailableDialog.width);
  });

  testWidgets('Escape closes the dialog without a choice', (tester) async {
    final result = await _open(tester, _texts(ReplayAvailability.geoBlocked));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Titre du dialogue'), findsNothing);
    expect(result.value, isNull);
  });
}
