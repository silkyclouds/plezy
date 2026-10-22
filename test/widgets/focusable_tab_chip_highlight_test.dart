import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';

Color _background(WidgetTester tester, String label) {
  final container = find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(FocusableTabChip)),
    matching: find.byType(AnimatedContainer),
  );
  return ((tester.widget<AnimatedContainer>(container).decoration) as BoxDecoration).color!;
}

double _brightness(Color color) => HSLColor.fromColor(color).lightness;

void main() {
  testWidgets('the chip under the cursor is brighter than a selected chip and than an idle one', (tester) async {
    final selectedNode = FocusNode(debugLabel: 'selected');
    final idleNode = FocusNode(debugLabel: 'idle');
    addTearDown(selectedNode.dispose);
    addTearDown(idleNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: InputModeTracker(
          child: Scaffold(
            body: Row(
              children: [
                FocusableTabChip(label: 'Selected', isSelected: true, focusNode: selectedNode, onSelect: () {}),
                FocusableTabChip(label: 'Idle', isSelected: false, focusNode: idleNode, onSelect: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    idleNode.requestFocus();
    await tester.pumpAndSettle();
    final selectedWhileAway = _brightness(_background(tester, 'Selected'));
    final focusedIdle = _brightness(_background(tester, 'Idle'));
    idleNode.unfocus();
    await tester.pumpAndSettle();
    final idleWhileAway = _brightness(_background(tester, 'Idle'));

    selectedNode.requestFocus();
    await tester.pumpAndSettle();
    final focusedSelected = _brightness(_background(tester, 'Selected'));

    expect(focusedIdle, greaterThan(selectedWhileAway));
    expect(focusedSelected, greaterThan(selectedWhileAway));
    expect(selectedWhileAway, greaterThan(idleWhileAway));
  });
}
