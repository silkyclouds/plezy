import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../widgets/app_icon.dart';
import '../settings/replay/replay_palette.dart';
import '../settings/replay/replay_pill.dart';
import 'replay_unavailable_texts.dart';

/// What the viewer picked in [ReplayUnavailableDialog].
enum ReplayUnavailableChoice { close, changeLocation, signIn }

/// Asks the viewer what to do about a title that cannot be played, in place of the player.
Future<ReplayUnavailableChoice?> showReplayUnavailableDialog(
  BuildContext context,
  ReplayUnavailableTexts texts, {
  required bool canSignIn,
}) {
  return showDialog<ReplayUnavailableChoice>(
    context: context,
    useRootNavigator: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => ReplayUnavailableDialog(texts: texts, canSignIn: canSignIn),
  );
}

/// Why a catch-up title cannot be played and the one or two things the viewer can do about it. The right-most button
/// has the focus when it opens; Back closes it.
class ReplayUnavailableDialog extends StatefulWidget {
  static const width = 640.0;

  final ReplayUnavailableTexts texts;
  final bool canSignIn;

  const ReplayUnavailableDialog({super.key, required this.texts, required this.canSignIn});

  @override
  State<ReplayUnavailableDialog> createState() => _ReplayUnavailableDialogState();
}

class _ReplayUnavailableDialogState extends State<ReplayUnavailableDialog> {
  late final List<(String, ReplayUnavailableChoice)> _buttons = _buttonsFor(widget);
  late final List<FocusNode> _nodes = [for (final _ in _buttons) FocusNode()];

  static List<(String, ReplayUnavailableChoice)> _buttonsFor(ReplayUnavailableDialog dialog) {
    final close = (t.replay.detail.dialog.close, ReplayUnavailableChoice.close);
    if (dialog.texts.offersLocationChange) {
      return [(t.replay.detail.dialog.changeLocation, ReplayUnavailableChoice.changeLocation), close];
    }
    if (dialog.texts.offersSignIn && dialog.canSignIn) {
      return [close, (t.replay.signIn, ReplayUnavailableChoice.signIn)];
    }
    return [close];
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusButton(int index) {
    if (index >= 0 && index < _nodes.length) _nodes[index].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final inset = MediaQuery.sizeOf(context).width - 80;
    final texts = widget.texts;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: inset < ReplayUnavailableDialog.width ? inset : ReplayUnavailableDialog.width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 48, offset: const Offset(0, 16)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppIcon(texts.icon, fill: 1, size: 32, color: palette.ink),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        texts.dialogTitle,
                        style: TextStyle(color: palette.ink, fontSize: 26, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(texts.dialogBody, style: TextStyle(color: palette.muted, fontSize: 18, height: 1.4)),
                const SizedBox(height: 32),
                Align(alignment: Alignment.centerRight, child: _buttonRow()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttonRow() {
    final last = _buttons.length - 1;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        for (var i = 0; i <= last; i++)
          ReplayPill(
            label: _buttons[i].$1,
            height: 48,
            fontSize: 18,
            horizontalPadding: 24,
            autofocus: i == last,
            focusNode: _nodes[i],
            onLeft: () => _focusButton(i - 1),
            onRight: () => _focusButton(i + 1),
            onPressed: () => Navigator.of(context).pop(_buttons[i].$2),
          ),
      ],
    );
  }
}
