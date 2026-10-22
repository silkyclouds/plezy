import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../utils/dialogs.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/replay_channel_logo.dart';
import 'replay_choice_row.dart';
import 'replay_country_phrases.dart';
import 'replay_dialog_frame.dart';
import 'replay_palette.dart';
import 'replay_pill.dart';
import 'replay_row.dart';
import 'replay_suggestion_rows.dart';

/// Opens the rows dialog of [info]; resolves to the viewer's selection, or null when they cancel.
Future<ReplayRowSelection?> showReplayRowsDialog(
  BuildContext context, {
  required ReplaySourceInfo info,
  required List<({String id, String title})> choices,
  required ReplayRowSelection initial,
  required int rowsPerChannel,
  required String locale,
}) => showScopedDialog<ReplayRowSelection>(
  context: context,
  builder: (_) => ReplayRowsDialog(
    info: info,
    choices: choices,
    initial: initial,
    rowsPerChannel: rowsPerChannel,
    locale: locale,
  ),
);

/// The rows one channel publishes, with a box each and a switch for the rows it adds later. Saving needs at least
/// one box ticked.
class ReplayRowsDialog extends StatefulWidget {
  final ReplaySourceInfo info;
  final List<({String id, String title})> choices;
  final ReplayRowSelection initial;
  final int rowsPerChannel;
  final String locale;

  const ReplayRowsDialog({
    super.key,
    required this.info,
    required this.choices,
    required this.initial,
    required this.rowsPerChannel,
    required this.locale,
  });

  @override
  State<ReplayRowsDialog> createState() => _ReplayRowsDialogState();
}

class _ReplayRowsDialogState extends State<ReplayRowsDialog> {
  final _cancel = FocusNode(debugLabel: 'ReplayRowsCancel');
  final _save = FocusNode(debugLabel: 'ReplayRowsSave');
  late ReplayRowSelection _selection = widget.initial;

  @override
  void dispose() {
    _cancel.dispose();
    _save.dispose();
    super.dispose();
  }

  bool get _canSave => _selection.ticked.isNotEmpty;

  void _toggle(String id) {
    final ticked = {..._selection.ticked};
    if (!ticked.remove(id)) ticked.add(id);
    setState(() => _selection = _selection.copyWith(ticked: ticked));
  }

  void _downFromList() => (_canSave ? _save : _cancel).requestFocus();

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final s = t.replay.suggestions;
    final count = widget.rowsPerChannel;
    return ReplayDialogFrame(
      width: 600,
      padding: 32,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReplayChannelLogo.tile(sourceId: widget.info.id, name: widget.info.name),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  s.rowsTitle(channel: replayChannelOf(widget.info.name, widget.locale)),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ReplayChoiceRow(
            label: s.includeNew,
            subtitle: _selection.includeNew ? s.includeNewOn : s.includeNewOff,
            height: 64,
            autofocus: true,
            trailing: (_) => ReplayRow.switchOf(_selection.includeNew),
            onPressed: () => setState(() => _selection = _selection.copyWith(includeNew: !_selection.includeNew)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              count == 1 ? s.limitOne : s.limitMany(count: count),
              style: TextStyle(color: palette.muted, fontSize: 16),
            ),
          ),
          if (widget.choices.isEmpty)
            Padding(padding: const EdgeInsets.all(14), child: Text(s.noRows, style: const TextStyle(fontSize: 17))),
          for (var i = 0; i < widget.choices.length; i++) _choice(i),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ReplayPill(
                focusNode: _cancel,
                label: t.common.cancel,
                height: 56,
                fontSize: 20,
                horizontalPadding: 32,
                onPressed: () => Navigator.pop(context),
                onRight: _canSave ? _save.requestFocus : null,
              ),
              const SizedBox(width: 16),
              ReplayPill(
                focusNode: _save,
                label: t.common.save,
                height: 56,
                fontSize: 20,
                horizontalPadding: 32,
                enabled: _canSave,
                onPressed: () => Navigator.pop(context, _selection),
                onLeft: _cancel.requestFocus,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choice(int index) {
    final choice = widget.choices[index];
    final on = _selection.ticked.contains(choice.id);
    return ReplayChoiceRow(
      label: choice.title,
      selected: on,
      leading: (ink) => AppIcon(
        on ? Symbols.check_box_rounded : Symbols.check_box_outline_blank_rounded,
        size: 26,
        color: ink,
      ),
      onDown: index == widget.choices.length - 1 ? _downFromList : null,
      onPressed: () => _toggle(choice.id),
    );
  }
}
