import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/input_mode_tracker.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_menu.dart';
import 'replay_choice_row.dart';

/// One choice of a [showReplayMenu] menu.
class ReplayMenuEntry<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// The current value: it gets a check mark and the initial focus.
  final bool selected;

  const ReplayMenuEntry({required this.value, required this.label, this.icon, this.selected = false});
}

/// The screen rectangle of the widget behind [context], used to anchor a menu to it.
Rect replayAnchorRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Shows a menu of 52 px rows anchored under [anchor]; resolves to the chosen value, or null when dismissed.
Future<T?> showReplayMenu<T>(
  BuildContext context, {
  required Rect anchor,
  required List<ReplayMenuEntry<T>> entries,
  double width = 320,
  AppMenuAnchorAlignment alignment = AppMenuAnchorAlignment.start,
}) {
  final focusRows = InputModeTracker.isKeyboardMode(context, listen: false);
  return showAnchoredPanel<T>(
    context,
    anchorRect: anchor,
    anchorAlignment: alignment,
    width: width,
    builder: (panelContext) => _ReplayMenuList<T>(
      entries: entries,
      focusRows: focusRows,
      onChosen: (value) => Navigator.pop(panelContext, value),
    ),
  );
}

class _ReplayMenuList<T> extends StatelessWidget {
  final List<ReplayMenuEntry<T>> entries;
  final bool focusRows;
  final ValueChanged<T> onChosen;

  const _ReplayMenuList({required this.entries, required this.focusRows, required this.onChosen});

  @override
  Widget build(BuildContext context) {
    final firstFocus = entries.indexWhere((entry) => entry.selected);
    final initial = firstFocus < 0 ? 0 : firstFocus;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++)
            ReplayChoiceRow(
              label: entries[i].label,
              selected: entries[i].selected,
              autofocus: focusRows && i == initial,
              leading: entries[i].icon == null ? null : (ink) => AppIcon(entries[i].icon, size: 24, color: ink),
              trailing: entries[i].selected ? (ink) => AppIcon(Symbols.check_rounded, size: 22, color: ink) : null,
              onUp: i == 0 ? () {} : null,
              onDown: i == entries.length - 1 ? () {} : null,
              onPressed: () => onChosen(entries[i].value),
            ),
        ],
      ),
    );
  }
}
