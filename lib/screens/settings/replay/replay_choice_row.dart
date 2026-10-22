import 'package:flutter/material.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_tile_mixin.dart';
import '../../../focus/input_mode_tracker.dart';
import '../../../focus/key_event_utils.dart';
import 'replay_palette.dart';

/// A row of a menu or dialog: transparent at rest, inverted (light fill, dark ink) when focused.
class ReplayChoiceRow extends StatefulWidget {
  final String label;
  final String? subtitle;

  /// Draw the icon or control at the start or end of the row in the ink of the current state.
  final Widget Function(Color ink)? leading;
  final Widget Function(Color ink)? trailing;
  final double height;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  /// Key overrides. Up and down keys that return true are consumed even without an action, to stop at list ends.
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final bool trapHorizontal;

  const ReplayChoiceRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.leading,
    this.trailing,
    this.height = 52,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.onUp,
    this.onDown,
    this.trapHorizontal = true,
  });

  @override
  State<ReplayChoiceRow> createState() => _ReplayChoiceRowState();
}

class _ReplayChoiceRowState extends State<ReplayChoiceRow> with FocusableTileStateMixin<ReplayChoiceRow> {
  bool _focused = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    effectiveFocusNode.addListener(_syncFocus);
  }

  @override
  void didUpdateWidget(ReplayChoiceRow oldWidget) {
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
    final showFocus = _focused && InputModeTracker.isKeyboardMode(context);
    final ink = showFocus ? palette.onFocus : palette.ink;
    final subtitle = widget.subtitle;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: Focus(
        focusNode: effectiveFocusNode,
        autofocus: widget.autofocus,
        onKeyEvent: (node, event) {
          if (SelectKeyUpSuppressor.consumeIfSuppressed(event)) return KeyEventResult.handled;
          return dpadKeyHandler(
            onSelect: widget.onPressed,
            onUp: widget.onUp,
            onDown: widget.onDown,
            trapHorizontalEdges: widget.trapHorizontal,
          )(node, event);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            constraints: BoxConstraints(minHeight: widget.height),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: showFocus ? palette.focus : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (widget.leading != null) ...[widget.leading!(ink), const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.label, style: TextStyle(color: ink, fontSize: 17)),
                      if (subtitle != null)
                        Text(subtitle, style: TextStyle(color: ink.withValues(alpha: 0.78), fontSize: 15)),
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[const SizedBox(width: 12), widget.trailing!(ink)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
