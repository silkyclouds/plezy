import 'package:flutter/material.dart';

import '../../../focus/focusable_tile_mixin.dart';
import '../../../focus/input_mode_tracker.dart';
import '../../../focus/key_event_utils.dart';
import 'replay_palette.dart';

/// One line of the catch-up settings: a 56 px lead column, a title with optional detail lines, and a trailing widget.
///
/// Focus draws a raised fill and a 2 px outline, never a darker fill. An inactive row keeps its place but is skipped
/// by the D-pad.
class ReplayRow extends StatefulWidget {
  /// Width of the lead column that holds a country code, a logo tile or an icon.
  static const leadWidth = 56.0;
  static const leadGap = 14.0;

  /// Space between the group edge and the row's focus outline.
  static const groupInset = 8.0;
  static const _outline = 2.0;
  static const _leadStart = 18.0;

  /// Distance from the group edge to the left edge of the text.
  static const textInset = groupInset + _outline + _leadStart + leadWidth + leadGap;

  final Widget? lead;
  final String title;
  final FontWeight? titleWeight;
  final List<Widget> details;
  final Widget? trailing;
  final double minHeight;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final String? semanticsLabel;

  const ReplayRow({
    super.key,
    required this.title,
    required this.onSelect,
    this.lead,
    this.titleWeight,
    this.details = const [],
    this.trailing,
    this.minHeight = 75,
    this.onLeft,
    this.onRight,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.semanticsLabel,
  });

  /// A switch that only displays the row's state: the row itself takes the focus and the press.
  static Widget switchOf(bool value, {bool enabled = true}) => ExcludeFocus(
    child: IgnorePointer(child: Switch(value: value, onChanged: enabled ? (_) {} : null)),
  );

  @override
  State<ReplayRow> createState() => _ReplayRowState();
}

class _ReplayRowState extends State<ReplayRow> with FocusableTileStateMixin<ReplayRow> {
  bool _focused = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    effectiveFocusNode.addListener(_syncFocus);
  }

  @override
  void didUpdateWidget(ReplayRow oldWidget) {
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
    final ink = enabled ? palette.ink : palette.inactive;
    final detailInk = enabled ? palette.muted : palette.inactive;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel,
      child: Focus(
        focusNode: effectiveFocusNode,
        canRequestFocus: enabled,
        autofocus: widget.autofocus && enabled,
        onKeyEvent: dpadKeyHandler(
          onSelect: enabled ? widget.onSelect : null,
          onLeft: enabled ? widget.onLeft : null,
          onRight: enabled ? widget.onRight : null,
        ),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? widget.onSelect : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ReplayRow.groupInset),
              child: Container(
                constraints: BoxConstraints(minHeight: widget.minHeight),
                padding: const EdgeInsets.fromLTRB(ReplayRow._leadStart, 8, 16, 8),
                decoration: BoxDecoration(
                  color: showFocus ? palette.raised : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: showFocus ? palette.ink : Colors.transparent,
                    width: ReplayRow._outline,
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: ink),
                  child: IconTheme.merge(
                    data: IconThemeData(color: ink),
                    child: Row(
                      children: [
                        SizedBox(width: ReplayRow.leadWidth, child: Center(child: widget.lead)),
                        const SizedBox(width: ReplayRow.leadGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(fontSize: 17, fontWeight: widget.titleWeight, height: 1.3),
                              ),
                              DefaultTextStyle.merge(
                                style: TextStyle(fontSize: 15, color: detailInk, height: 1.35),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: widget.details,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.trailing != null) ...[const SizedBox(width: 12), widget.trailing!],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
