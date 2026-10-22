import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/replay/auth/replay_auth.dart';
import 'package:plezy/replay/provider/replay_provider_registry.dart';
import 'package:plezy/screens/settings/replay/replay_sign_in_dialog.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';

Widget _app(Future<void> Function(String, String) onSubmit) => InputModeTracker(
  child: MaterialApp(
    theme: monoTheme(MonoPalette.dark),
    home: Scaffold(
      body: ReplaySignInDialog(info: replaySourceInfo('rtlplay')!, onSubmit: onSubmit),
    ),
  ),
);

Future<void> _noop(String login, String password) async {}

TextField _field(WidgetTester tester, int index) => tester.widget<TextField>(find.byType(TextField).at(index));

void main() {
  tearDown(() => TvDetectionService.setForceTVSync(false));

  testWidgets('On TV, select on the login field attaches text input', (tester) async {
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
    await tester.pumpWidget(_app(_noop));
    await tester.pumpAndSettle();
    tester.testTextInput.log.clear();

    expect(_field(tester, 0).readOnly, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(_field(tester, 0).readOnly, isFalse);
    expect(tester.testTextInput.log.map((call) => call.method), contains('TextInput.setClient'));
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('Down goes from the e-mail to the password, then to Sign in', (tester) async {
    await tester.pumpWidget(_app(_noop));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText).at(1)).focusNode.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    final cancel = find.text('Cancel');
    expect(Focus.of(tester.element(cancel)).hasPrimaryFocus, isTrue);
  });

  testWidgets('A refusal keeps the dialog, clears the password and refocuses it', (tester) async {
    await tester.pumpWidget(
      _app((login, password) async => throw const ReplayAuthException(ReplayAuthFailure.invalidCredentials)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'marie@example.be');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('RTL Play refused these credentials.'), findsOneWidget);
    expect(_field(tester, 1).controller!.text, isEmpty);
    expect(tester.widget<EditableText>(find.byType(EditableText).at(1)).focusNode.hasPrimaryFocus, isTrue);
  });
}
