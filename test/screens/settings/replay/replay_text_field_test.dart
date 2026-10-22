import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/screens/settings/replay/replay_text_field.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';

void main() {
  tearDown(() => TvDetectionService.setForceTVSync(false));

  testWidgets('The field is a plain text field', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(
          body: ReplayTextField(controller: controller, hint: 'Search'),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('On TV, a focused search field is editable and attaches text input', (tester) async {
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

    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(tester.testTextInput.log.map((call) => call.method), contains('TextInput.setClient'));
  });

  testWidgets('Typed text reaches the controller, in TV mode too', (tester) async {
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(body: ReplayTextField(controller: controller, autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'raph@example.org');

    expect(controller.text, 'raph@example.org');
  });

  testWidgets('Down and up leave the field, right only from the end of the text', (tester) async {
    final controller = TextEditingController(text: 'abc');
    addTearDown(controller.dispose);
    final left = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(
          body: ReplayTextField(
            controller: controller,
            autofocus: true,
            onNavigateDown: () => left.add('down'),
            onNavigateUp: () => left.add('up'),
            onNavigateRight: () => left.add('right'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    expect(left, ['down', 'up', 'right']);
  });
}
