import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/provider/replay_provider_registry.dart';
import 'package:plezy/utils/media_server_http_client.dart';

void main() {
  test('every listed source has a provider and the ids match', () {
    final http = MediaServerHttpClient();
    final providers = buildReplayProviders(replaySourceIds, http);
    expect(providers.keys, replaySourceIds);
    for (final info in replaySourceInfos) {
      expect(providers[info.id]!.source.id, info.id);
      expect(providers[info.id]!.source.name, info.name);
      expect(providers[info.id]!.source.support, info.support, reason: info.id);
    }
    http.close();
  });

  test('source ids are unique', () {
    expect(replaySourceIds.toSet(), hasLength(replaySourceIds.length));
  });
}
