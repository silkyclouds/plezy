import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../connection/connection.dart';
import '../../../connection/connection_registry.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../replay/client/replay_client.dart';
import '../../../replay/provider/replay_provider_registry.dart';
import 'replay_suggestions_screen.dart';

/// The catch-up client of the active profile, or null when catch-up TV is not set up.
ReplayClient? replayClientOf(BuildContext context) =>
    context.read<MultiServerProvider>().serverManager.getClient(ServerId(ReplayConnection.singletonId))
        as ReplayClient?;

/// Opens the home suggestions screen, with [focusChannel] focused when given. Does nothing without a catch-up
/// connection.
Future<void> openReplaySuggestionSettings(BuildContext context, {String? focusChannel}) async {
  final client = replayClientOf(context);
  final connection = await context.read<ConnectionRegistry>().get(ReplayConnection.singletonId);
  if (client == null || connection is! ReplayConnection || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReplaySuggestionsScreen(
        store: client.suggestionSettings,
        automaticLanguages: client.automaticSuggestionLanguages,
        rowChoices: client.suggestionRowChoices,
        channels: [for (final id in connection.enabledSources) ?replaySourceInfo(id)],
        locale: LocaleSettings.currentLocale.languageCode,
        focusChannel: focusChannel,
      ),
    ),
  );
}
