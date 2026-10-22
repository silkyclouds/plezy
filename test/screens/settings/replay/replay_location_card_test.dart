import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/screens/settings/replay/replay_location_card.dart';
import 'package:plezy/theme/mono_theme.dart';

Future<List<String?>> _pump(
  WidgetTester tester, {
  String? country = 'BE',
  bool overridden = false,
  bool openMenu = false,
}) async {
  final choices = <String?>[];
  await tester.pumpWidget(
    InputModeTracker(
      child: MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(
          body: ReplayLocationCard(
            country: country,
            overridden: overridden,
            detected: 'BE',
            countries: const ['BE', 'DE', 'FR'],
            locale: 'en',
            openMenuOnShow: openMenu,
            onChanged: choices.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return choices;
}

void main() {
  testWidgets('The detected country is named with the warning rule', (tester) async {
    await _pump(tester);

    expect(find.text('Your location: Belgium'), findsOneWidget);
    expect(
      find.text('Detected from your connection. Channels that do not play from Belgium carry a warning.'),
      findsOneWidget,
    );
  });

  testWidgets('A country chosen by hand shows what was detected', (tester) async {
    await _pump(tester, country: 'FR', overridden: true);

    expect(find.text('Your location: France'), findsOneWidget);
    expect(find.text('Chosen by hand. Detection: Belgium'), findsOneWidget);
  });

  testWidgets('Change opens a menu with automatic detection and the countries', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(find.text('Automatic detection (Belgium)'), findsOneWidget);
    expect(find.text('Germany'), findsOneWidget);
  });

  testWidgets('Choosing a country reports its code, automatic reports null', (tester) async {
    final choices = await _pump(tester);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('France'));
    await tester.pumpAndSettle();
    expect(choices, ['FR']);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic detection (Belgium)'));
    await tester.pumpAndSettle();
    expect(choices, ['FR', null]);
  });

  testWidgets('The menu can open as soon as the card is shown and Back closes it', (tester) async {
    await _pump(tester, openMenu: true);
    expect(find.text('Automatic detection (Belgium)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Automatic detection (Belgium)'), findsNothing);
  });
}
