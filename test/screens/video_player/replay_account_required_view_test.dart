import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/video_player/widgets/replay_account_required_view.dart';

Widget _view({
  bool accountRefused = false,
  Duration? resume = const Duration(minutes: 12, seconds: 40),
  Future<bool> Function()? onSignIn,
  VoidCallback? onSignedIn,
  VoidCallback? onBack,
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: ReplayAccountRequiredView(
      sourceId: 'rtlplay',
      channelName: 'RTL Play',
      programmeTitle: 'Cache Cash',
      resumePosition: resume,
      accountRefused: accountRefused,
      onSignIn: onSignIn ?? () async => false,
      onSignedIn: onSignedIn ?? () {},
      onBack: onBack ?? () {},
    ),
  );
}

FocusNode? _focusedNode() => FocusManager.instance.primaryFocus;

bool _focusIsOn(WidgetTester tester, String label) {
  final context = _focusedNode()?.context;
  if (context == null) return false;
  return find
      .descendant(of: find.byElementPredicate((e) => e == context), matching: find.text(label))
      .evaluate()
      .isNotEmpty;
}

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('names the channel, the programme and the resume position', (tester) async {
    await tester.pumpWidget(_view());
    await tester.pumpAndSettle();

    expect(find.text('This programme needs a RTL Play account'), findsOneWidget);
    expect(find.textContaining('“Cache Cash”'), findsOneWidget);
    expect(find.textContaining('resume at 12:40'), findsOneWidget);
  });

  testWidgets('starts from the beginning when nothing was watched', (tester) async {
    await tester.pumpWidget(_view(resume: null));
    await tester.pumpAndSettle();

    expect(find.textContaining('start from the beginning'), findsOneWidget);
    expect(find.textContaining('resume at'), findsNothing);
  });

  testWidgets('a refused account gets the change-account variant', (tester) async {
    await tester.pumpWidget(_view(accountRefused: true));
    await tester.pumpAndSettle();

    expect(find.text('Your RTL Play account cannot watch this programme'), findsOneWidget);
    expect(find.text('Change account'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('focus starts on the sign-in button', (tester) async {
    await tester.pumpWidget(_view());
    await tester.pumpAndSettle();

    expect(_focusIsOn(tester, 'Sign in'), isTrue);
  });

  testWidgets('left and right switch buttons, up and down do nothing', (tester) async {
    await tester.pumpWidget(_view());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_focusIsOn(tester, 'Sign in'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_focusIsOn(tester, 'Back'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focusIsOn(tester, 'Back'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_focusIsOn(tester, 'Sign in'), isTrue);
  });

  testWidgets('a successful sign-in hands control back to the player', (tester) async {
    var signedIn = 0;
    await tester.pumpWidget(_view(onSignIn: () async => true, onSignedIn: () => signedIn++));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(signedIn, 1);
  });

  testWidgets('a cancelled sign-in keeps the screen and the focus', (tester) async {
    var signedIn = 0;
    await tester.pumpWidget(_view(onSignIn: () async => false, onSignedIn: () => signedIn++));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(signedIn, 0);
    expect(_focusIsOn(tester, 'Sign in'), isTrue);
  });

  testWidgets('the sign-in button reads Signing in while the dialog is open', (tester) async {
    final done = Completer<bool>();
    await tester.pumpWidget(_view(onSignIn: () => done.future));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Signing in…'), findsOneWidget);

    done.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the back button and the back key both leave', (tester) async {
    var left = 0;
    await tester.pumpWidget(_view(onBack: () => left++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(left, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(left, 2);
  });
}
