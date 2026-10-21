import '../../utils/media_server_http_client.dart';
import '../providers/arte/arte_provider.dart';
import 'replay_provider.dart';

/// Source ids the app knows how to build, in the order they are offered to the user.
const replaySourceIds = ['arte'];

/// Display name of a source id, for pickers shown before any provider exists.
String replaySourceName(String id) => switch (id) {
  'arte' => 'ARTE',
  _ => id,
};

/// Builds the providers for the sources a connection enables. Unknown ids are skipped.
Map<String, ReplayProvider> buildReplayProviders(Iterable<String> enabledSources, MediaServerHttpClient http) {
  final providers = <String, ReplayProvider>{};
  for (final id in enabledSources) {
    final provider = switch (id) {
      'arte' => ArteProvider(http),
      _ => null,
    };
    if (provider != null) providers[id] = provider;
  }
  return providers;
}
