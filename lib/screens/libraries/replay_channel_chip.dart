import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../media/media_library.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/focusable_tab_chip.dart';

/// The broadcaster picker of the Catch-up TV screen: the channel being browsed, as a chip that opens the list of
/// channels. It sits in front of the tab chips so the channel name is always visible and reachable by D-pad.
class ReplayChannelChip extends StatelessWidget {
  final List<MediaLibrary> channels;
  final MediaLibrary selected;
  final FocusNode focusNode;
  final ValueChanged<String> onSelected;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateRight;
  final VoidCallback onNavigateDown;
  final VoidCallback? onNavigateUp;

  const ReplayChannelChip({
    super.key,
    required this.channels,
    required this.selected,
    required this.focusNode,
    required this.onSelected,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    required this.onNavigateDown,
    this.onNavigateUp,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (chipContext) => FocusableTabChip(
        label: selected.title,
        isSelected: true,
        focusNode: focusNode,
        onSelect: () => _openMenu(chipContext),
        onNavigateLeft: onNavigateLeft,
        onNavigateRight: onNavigateRight,
        onNavigateDown: onNavigateDown,
        onNavigateUp: onNavigateUp,
      ),
    );
  }

  Future<void> _openMenu(BuildContext chipContext) async {
    final box = chipContext.findRenderObject() as RenderBox?;
    if (box == null) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final choice = await showAdaptiveAppMenu<String>(
      chipContext,
      entries: [
        for (final channel in channels)
          AppMenuItem<String>(
            value: channel.globalKey,
            icon: Symbols.live_tv_rounded,
            label: channel.title,
            selected: channel.globalKey == selected.globalKey,
          ),
      ],
      anchorRect: Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height),
      focusFirstItem: true,
    );
    if (choice != null) onSelected(choice);
  }
}
