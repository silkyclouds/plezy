import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focusable_text_field.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/screens/settings/replay/replay_text_field.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';

void main() {
  tearDown(() => TvDetectionService.setForceTVSync(false));

  testWidgets('The field is a Plezy focusable text field', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(body: ReplayTextField(controller: controller, hint: 'Search')),
      ),
    );

    expect(find.byType(FocusableTextField), findsOneWidget);
  });

  testWidgets('On TV, select on the search field attaches text input', (tester) async {
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark),
          home: Scaffold(
            body: ReplayTextField(controller: controller, hint: 'Search', autofocus: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.testTextInput.log.clear();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(tester.testTextInput.log.map((call) => call.method), contains('TextInput.setClient'));
  });
}
