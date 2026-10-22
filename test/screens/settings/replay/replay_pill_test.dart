import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/screens/settings/replay/replay_pill.dart';
import 'package:plezy/theme/mono_theme.dart';

Color? _fill(WidgetTester tester) {
  final box = tester.widget<Container>(find.descendant(of: find.byType(ReplayPill), matching: find.byType(Container)));
  return (box.decoration as BoxDecoration).color;
}

Future<void> _pump(WidgetTester tester, {bool selected = false, bool enabled = true}) => tester.pumpWidget(
  InputModeTracker(
    child: MaterialApp(
      theme: monoTheme(MonoPalette.dark),
      home: Scaffold(
        body: Column(
          children: [
            ReplayPill(label: 'One', selected: selected, enabled: enabled, autofocus: true, onPressed: () {}),
            ReplayPill(label: 'Two', onPressed: () {}),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('A focused pill is filled with the focus color and is lighter than a chosen one', (tester) async {
    await _pump(tester, selected: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final focused = _fill(tester);

    expect(focused, Theme.of(tester.element(find.byType(ReplayPill).first)).colorScheme.primary);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final chosen = _fill(tester);

    expect(focused!.computeLuminance(), greaterThan(chosen!.computeLuminance()));
  });

  testWidgets('An inactive pill is skipped by the D-pad', (tester) async {
    await _pump(tester, enabled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(Focus.of(tester.element(find.text('Two'))).hasPrimaryFocus, isTrue);
  });
}
