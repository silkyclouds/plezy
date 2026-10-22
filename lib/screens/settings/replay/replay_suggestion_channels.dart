import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../replay/suggestions/replay_suggestion_settings.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/replay_channel_logo.dart';
import 'replay_palette.dart';
import 'replay_row.dart';
import 'replay_suggestion_rows.dart';
import 'replay_suggestion_view.dart';

/// The list of enabled channels of the suggestions screen: a switch per channel with the reason it is on or off, and
/// under it the rows choice and, when the viewer overrode the language rule, the way back.
class ReplaySuggestionChannels extends StatelessWidget {
  final List<ReplaySourceInfo> channels;
  final ReplaySuggestionSettings settings;
  final Set<String> automatic;
  final String locale;

  /// Row titles per channel, for the channels whose rows were fetched.
  final Map<String, Map<String, String>> titles;
  final FocusNode Function(String sourceId) focusNodeFor;
  final void Function(ReplaySourceInfo info, bool on) onToggle;
  final void Function(ReplaySourceInfo info) onEditRows;
  final void Function(ReplaySourceInfo info) onResetChoice;

  const ReplaySuggestionChannels({
    super.key,
    required this.channels,
    required this.settings,
    required this.automatic,
    required this.locale,
    required this.titles,
    required this.focusNodeFor,
    required this.onToggle,
    required this.onEditRows,
    required this.onResetChoice,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final master = settings.enabled;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: palette.group, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final info in channels) ..._channel(info, master)],
      ),
    );
  }

  List<Widget> _channel(ReplaySourceInfo info, bool master) {
    final stance = channelStance(settings, info, automatic);
    return [
      ReplayRow(
        key: ValueKey('channel-${info.id}'),
        focusNode: focusNodeFor(info.id),
        enabled: master,
        lead: ReplayChannelLogo.tile(sourceId: info.id, name: info.name),
        title: info.name,
        semanticsLabel: '${info.name}, ${t.replay.suggestions.title}',
        details: [Text(stance.line(locale))],
        trailing: ReplayRow.switchOf(stance.offered, enabled: master),
        onSelect: () => onToggle(info, !stance.offered),
      ),
      if (stance.offered)
        ReplayRow(
          key: ValueKey('rows-${info.id}'),
          enabled: master,
          minHeight: 56,
          lead: const AppIcon(Symbols.list_rounded, size: 24),
          title: rowsSummaryLine(settings, info.id, titles[info.id]),
          trailing: const AppIcon(Symbols.chevron_right_rounded, size: 28),
          onSelect: () => onEditRows(info),
        ),
      if (settings.channels.containsKey(info.id))
        ReplayRow(
          key: ValueKey('reset-${info.id}'),
          enabled: master,
          minHeight: 56,
          lead: const AppIcon(Symbols.restart_alt_rounded, size: 24),
          title: t.replay.suggestions.backToRule,
          onSelect: () => onResetChoice(info),
        ),
    ];
  }
}
