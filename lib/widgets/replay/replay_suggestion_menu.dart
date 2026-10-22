import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_hub.dart';
import '../../providers/multi_server_provider.dart';
import '../../replay/client/replay_client.dart';
import '../../replay/suggestions/replay_home_suggestions.dart';
import '../../replay/suggestions/replay_suggestion_events.dart';
import '../../replay/suggestions/replay_suggestion_settings.dart';
import '../../screens/settings/replay_settings_screen.dart';
import '../media_context_menu.dart';

/// The card menu actions that let the viewer shape the catch-up rows of the home screen: stop one row, stop a whole
/// channel, or open the settings. Empty for any row that is not a suggestion.
List<MediaMenuExtraEntry> replaySuggestionMenuEntries(BuildContext context, MediaHub hub) {
  if (!ReplayHomeSuggestions.isSuggestion(hub)) return const [];
  final colon = hub.id.indexOf(':');
  if (colon < 0) return const [];
  final sourceId = hub.id.substring(0, colon);
  return [
    MediaMenuExtraEntry(
      icon: Symbols.visibility_off_rounded,
      label: t.replay.homeRow.hideRow,
      onSelected: () => unawaited(_change(context, hub, (s) => _withMutedRow(s, hub.id))),
    ),
    MediaMenuExtraEntry(
      icon: Symbols.block_rounded,
      label: t.replay.homeRow.hideChannel,
      onSelected: () => unawaited(_change(context, hub, (s) => _withChannelOff(s, sourceId))),
    ),
    MediaMenuExtraEntry(
      icon: Symbols.tune_rounded,
      label: t.replay.homeRow.tune,
      onSelected: () =>
          unawaited(Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const ReplaySettingsScreen()))),
    ),
  ];
}

ReplaySuggestionSettings _withMutedRow(ReplaySuggestionSettings s, String rowKey) =>
    s.copyWith(mutedRows: {...s.mutedRows, rowKey});

ReplaySuggestionSettings _withChannelOff(ReplaySuggestionSettings s, String sourceId) =>
    s.copyWith(channels: {...s.channels, sourceId: false});

/// Applies [change], saves it, tells the home screen to rebuild, and offers to undo from a snackbar.
Future<void> _change(
  BuildContext context,
  MediaHub hub,
  ReplaySuggestionSettings Function(ReplaySuggestionSettings) change,
) async {
  final serverId = serverIdOrNull(hub.serverId);
  final client = serverId == null ? null : context.read<MultiServerProvider?>()?.serverManager.getClient(serverId);
  if (client is! ReplayClient) return;
  final before = await client.suggestionSettings.load();
  await client.suggestionSettings.save(change(before));
  notifyReplaySuggestionsChanged();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(t.replay.homeRow.hidden(row: hub.title)),
      action: SnackBarAction(
        label: t.replay.homeRow.undo,
        onPressed: () async {
          await client.suggestionSettings.save(before);
          notifyReplaySuggestionsChanged();
        },
      ),
    ),
  );
}
