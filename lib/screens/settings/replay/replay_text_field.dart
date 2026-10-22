import 'package:flutter/material.dart';

import '../../../focus/focusable_text_field.dart';
import 'replay_palette.dart';

/// A single-line field of fixed height whose fill and outline follow focus: resting on the group fill, a lighter fill
/// with a 2 px outline when focused.
class ReplayTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final double height;
  final double fontSize;
  final String? hint;
  final IconData? prefixIcon;
  final bool obscure;
  final bool enabled;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateRight;

  /// A control placed inside the field, after the text (the password eye).
  final Widget? trailing;

  const ReplayTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.height = 52,
    this.fontSize = 18,
    this.hint,
    this.prefixIcon,
    this.obscure = false,
    this.enabled = true,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onNavigateRight,
    this.trailing,
  });

  @override
  State<ReplayTextField> createState() => _ReplayTextFieldState();
}

class _ReplayTextFieldState extends State<ReplayTextField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final ink = widget.enabled ? palette.ink : palette.inactive;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _focused ? palette.fieldFocus : palette.group,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _focused ? palette.ink : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            if (widget.prefixIcon != null) ...[
              Icon(widget.prefixIcon, size: 24, color: palette.muted),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FocusableTextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: widget.autofocus,
                enabled: widget.enabled,
                // Only OK opens the TV keyboard, so moving the D-pad over the field never raises it.
                tvTextInputAutoOpenBehavior: TvTextInputAutoOpenBehavior.never,
                obscureText: widget.obscure,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                onNavigateDown: widget.onNavigateDown,
                onNavigateUp: widget.onNavigateUp,
                onNavigateRight: widget.onNavigateRight,
                style: TextStyle(color: ink, fontSize: widget.fontSize),
                decoration: InputDecoration.collapsed(
                  hintText: widget.hint,
                  hintStyle: TextStyle(color: palette.muted, fontSize: widget.fontSize),
                ),
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ),
    );
  }
}
