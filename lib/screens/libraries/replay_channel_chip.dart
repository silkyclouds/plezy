import 'package:flutter/material.dart';

import '../../focus/focusable_chip_mixin.dart';
import '../../focus/input_mode_tracker.dart';
import '../../media/media_library.dart';
import '../../widgets/focus_builders.dart';
import '../../widgets/replay_channel_logo.dart';
import 'replay_channel_menu.dart';

/// The broadcaster picker of the Catch-up TV screen: the channel being browsed, as a chip that opens the list of
/// channels. It sits in front of the tab chips so the channel is always visible and reachable by D-pad. The chip shows
/// the channel's logo, or its name when no logo is bundled.
class ReplayChannelChip extends StatefulWidget {
  static const height = 44.0;

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
  State<ReplayChannelChip> createState() => _ReplayChannelChipState();
}

class _ReplayChannelChipState extends State<ReplayChannelChip> with FocusableChipStateMixin<ReplayChannelChip> {
  bool _menuOpen = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  String get debugLabel => 'replay_channel_chip';

  Future<void> _openMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || _menuOpen) return;
    final topLeft = box.localToGlobal(Offset.zero);
    setState(() => _menuOpen = true);
    final choice = await showReplayChannelMenu(
      context,
      anchorRect: Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height),
      channels: widget.channels,
      selectedKey: widget.selected.globalKey,
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    focusNode.requestFocus();
    if (choice != null) widget.onSelected(choice);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showFocus = isFocused && InputModeTracker.isKeyboardMode(context);
    // Focus is the strongest state; the open list holds the focus, so the chip then reads as selected.
    final Color fill;
    final Color ink;
    if (showFocus) {
      fill = scheme.primary;
      ink = scheme.onPrimary;
    } else if (_menuOpen) {
      fill = Color.alphaBlend(scheme.primary.withValues(alpha: 0.12), scheme.surfaceContainerHighest);
      ink = scheme.onSurface;
    } else {
      fill = scheme.surfaceContainerHighest;
      ink = scheme.onSurface;
    }
    final channel = widget.selected;
    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: (node, event) => handleChipKeyEvent(
        node,
        event,
        ChipKeyCallbacks(
          onSelect: _openMenu,
          onNavigateLeft: widget.onNavigateLeft,
          onNavigateRight: widget.onNavigateRight,
          onNavigateDown: widget.onNavigateDown,
          onNavigateUp: widget.onNavigateUp,
        ),
      ),
      onTap: _openMenu,
      semanticLabel: channel.title,
      selected: _menuOpen,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      backgroundColor: fill,
      borderRadius: ReplayChannelChip.height / 2,
      child: SizedBox(
        height: ReplayChannelChip.height,
        child: Center(
          widthFactor: 1,
          child: ReplayChannelLogo.inline(
            sourceId: channel.id,
            name: channel.title,
            color: ink,
            textStyle: TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
