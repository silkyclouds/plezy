import 'package:flutter/material.dart';

import '../../../focus/focusable_tile_mixin.dart';
import '../../../focus/input_mode_tracker.dart';
import '../../../focus/key_event_utils.dart';
import 'replay_palette.dart';

/// A rounded chip or button: resting, chosen, focused (inverted) and inactive (greyed and skipped by the D-pad).
class ReplayPill extends StatefulWidget {
  final String label;

  /// Draws an icon or logo in the ink of the current state.
  final Widget Function(Color ink)? lead;
  final double height;
  final double fontSize;
  final double horizontalPadding;
  final bool selected;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onDown;

  const ReplayPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.lead,
    this.height = 44,
    this.fontSize = 17,
    this.horizontalPadding = 20,
    this.selected = false,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.onLeft,
    this.onRight,
    this.onDown,
  });

  @override
  State<ReplayPill> createState() => _ReplayPillState();
}

class _ReplayPillState extends State<ReplayPill> with FocusableTileStateMixin<ReplayPill> {
  bool _focused = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    effectiveFocusNode.addListener(_syncFocus);
  }

  @override
  void didUpdateWidget(ReplayPill oldWidget) {
    final rebinds = oldWidget.focusNode != widget.focusNode;
    if (rebinds) effectiveFocusNode.removeListener(_syncFocus);
    super.didUpdateWidget(oldWidget);
    if (rebinds) {
      effectiveFocusNode.addListener(_syncFocus);
      _focused = effectiveFocusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    effectiveFocusNode.removeListener(_syncFocus);
    super.dispose();
  }

  void _syncFocus() {
    final focused = effectiveFocusNode.hasFocus;
    if (_focused != focused) setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final enabled = widget.enabled;
    final showFocus = enabled && _focused && InputModeTracker.isKeyboardMode(context);
    final fill = showFocus ? palette.focus : (widget.selected ? palette.selected : palette.idle);
    final ink = !enabled ? palette.inactive : (showFocus ? palette.onFocus : palette.ink);

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      child: Focus(
        focusNode: effectiveFocusNode,
        canRequestFocus: enabled,
        autofocus: widget.autofocus && enabled,
        onKeyEvent: dpadKeyHandler(
          onSelect: enabled ? widget.onPressed : null,
          onLeft: enabled ? widget.onLeft : null,
          onRight: enabled ? widget.onRight : null,
          onDown: enabled ? widget.onDown : null,
        ),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? widget.onPressed : null,
            child: Container(
              height: widget.height,
              padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
              decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(widget.height / 2)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.lead != null) ...[widget.lead!(ink), const SizedBox(width: 8)],
                  Text(
                    widget.label,
                    maxLines: 1,
                    style: TextStyle(color: ink, fontSize: widget.fontSize, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
