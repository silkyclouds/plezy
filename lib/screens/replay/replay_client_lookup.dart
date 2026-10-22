import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../providers/multi_server_provider.dart';
import '../../replay/client/replay_client.dart';
import 'replay_blocking.dart';
import 'replay_unavailable_texts.dart';

/// The catch-up client that serves [item], or null when there is none (offline, another backend, no provider).
ReplayClient? replayClientFor(BuildContext context, MediaItem item) {
  final serverId = serverIdOrNull(item.serverId);
  if (serverId == null) return null;
  final manager = context.read<MultiServerProvider?>()?.serverManager;
  final client = manager?.getClient(serverId);
  return client is ReplayClient ? client : null;
}

/// Sign-in state of [client], for [replayBlockerOf]. Without a client nobody is signed in.
ReplaySignedIn replaySignedInOf(ReplayClient? client) =>
    (sourceId) => client?.accounts.accountLabel(sourceId) != null;

/// Where [client] places the viewer.
ReplayViewerPlace replayPlaceOf(ReplayClient? client) =>
    ReplayViewerPlace(country: client?.geo?.country, chosen: client?.geo?.override != null);

/// Whether the viewer can sign in to the broadcaster of [item] from the app.
bool replayCanSignIn(ReplayClient? client, MediaItem item) =>
    client != null && client.accounts.supportsAccount(replaySourceIdOf(item) ?? '');
