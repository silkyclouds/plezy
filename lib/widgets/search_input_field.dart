import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_button.dart';
import '../focus/focusable_text_field.dart';
import 'app_icon.dart';
import 'pill_input_decoration.dart';
import 'voice_search_button.dart';

/// The pill search field the search screens put above their results, with the
/// clear affordance that appears once there is text: RIGHT out of the field
/// lands on it, LEFT goes back, and both escape down into the results.
///
/// [onBack] stays null unless the host wants the back key — a pushed route
/// needs it for its own pop.
class SearchInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;

  /// Names the clear button's focus node.
  final String debugLabel;

  final TvTextInputController? tvTextInputController;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onBack;

  const SearchInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.debugLabel,
    this.tvTextInputController,
    this.onNavigateLeft,
    this.onNavigateDown,
    this.onEditingComplete,
    this.onBack,
  });

  @override
  State<SearchInputField> createState() => _SearchInputFieldState();
}

class _SearchInputFieldState extends State<SearchInputField> {
  late final FocusNode _clearFocusNode = FocusNode(debugLabel: '${widget.debugLabel}.clear');
  late final FocusNode _micFocusNode = FocusNode(debugLabel: '${widget.debugLabel}.mic');
  bool _hasMic = false;

  @override
  void dispose() {
    _clearFocusNode.dispose();
    _micFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    widget.controller.clear();
    widget.focusNode.requestFocus();
  }

  void _applyTranscript(String text) {
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onEditingComplete?.call();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    final trailingButtons = (hasText ? 1 : 0) + (_hasMic ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          FocusableTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            tvTextInputController: widget.tvTextInputController,
            textInputAction: TextInputAction.search,
            onNavigateLeft: widget.onNavigateLeft,
            onNavigateRight: _hasMic
                ? _micFocusNode.requestFocus
                : hasText
                ? _clearFocusNode.requestFocus
                : null,
            onNavigateDown: widget.onNavigateDown,
            onEditingComplete: widget.onEditingComplete,
            onBack: widget.onBack,
            decoration: pillInputDecoration(
              context,
              hintText: widget.hintText,
              prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
              suffixIcon: trailingButtons > 0 ? SizedBox(width: 48.0 * trailingButtons) : null,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VoiceSearchButton(
                focusNode: _micFocusNode,
                onTranscript: _applyTranscript,
                onAvailabilityChanged: (available) {
                  if (mounted && available != _hasMic) setState(() => _hasMic = available);
                },
                onNavigateLeft: widget.focusNode.requestFocus,
                onNavigateRight: hasText ? _clearFocusNode.requestFocus : null,
                onNavigateDown: widget.onNavigateDown,
              ),
              if (hasText)
                FocusableButton(
                  focusNode: _clearFocusNode,
                  onPressed: _clearSearch,
                  onNavigateLeft: _hasMic ? _micFocusNode.requestFocus : widget.focusNode.requestFocus,
                  onNavigateDown: widget.onNavigateDown,
                  autoScroll: false,
                  child: IconButton(icon: const AppIcon(Symbols.clear_rounded, fill: 1), onPressed: _clearSearch),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
