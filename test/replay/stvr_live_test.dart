import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/stvr/stvr_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real STVR archive. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/stvr_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test(
    'the archive serves a show down to a stream or a geo verdict',
    () async {
      final provider = StvrProvider(MediaServerHttpClient());
      final rails = await provider.home();
      expect(rails, isNotEmpty);

      final hits = await provider.search('správy');
      final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
      final seasons = await provider.children(show.ref);
      expect(seasons, isNotEmpty);
      final episodes = await provider.children(seasons.first.ref);
      expect(episodes, isNotEmpty);
      expect(episodes.first.episodeNumber, isNotNull);

      final tally = <ReplayAvailability, int>{};
      final sample = (await provider.listing(replayAllBrowseId)).titles.take(12).toList();
      for (final episode in sample) {
        final playback = await provider.playback(episode.ref);
        tally.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
        if (!playback.isPlayable) continue;
        final master = await MediaServerHttpClient().get(playback.streams.first.url.toString());
        expect(master.statusCode, 200);
        expect(master.data.toString(), startsWith('#EXTM3U'));
      }
      // ignore: avoid_print
      print('STVR live availability of ${sample.length} latest recordings: $tally');
      expect(tally[ReplayAvailability.playable] ?? 0, greaterThan(0));
    },
    skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
