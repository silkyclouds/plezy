import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/tvlocales/antennecentre_provider.dart';
import 'package:plezy/replay/providers/tvlocales/canalzoom_provider.dart';
import 'package:plezy/replay/providers/tvlocales/telemb_provider.dart';
import 'package:plezy/replay/providers/tvlocales/telesambre_provider.dart';
import 'package:plezy/replay/providers/tvlocales/tvcom_provider.dart';
import 'package:plezy/replay/providers/tvlocales/tvlux_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _showsToSample = 8;

/// Talks to the real station sites and Freecaster. Run with
/// `PLEZY_LIVE_TESTS=1 flutter test test/replay/tvlocales_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  final http = MediaServerHttpClient();
  final providers = <ReplayProvider>[
    TvLuxProvider(http),
    TeleMbProvider(http),
    TelesambreProvider(http),
    TvcomProvider(http),
    AntenneCentreProvider(http),
    CanalZoomProvider(http),
  ];

  for (final provider in providers) {
    test('${provider.source.id} lists shows and plays an episode', () async {
      final shows = await provider.listing(replayAllBrowseId);
      expect(shows.totalCount, greaterThan(5));
      expect((await provider.home()).expand((r) => r.titles), isNotEmpty);

      var withEpisodes = 0;
      var playable = 0;
      var tried = 0;
      var failed = 0;
      for (final show in shows.titles.take(_showsToSample)) {
        try {
          final seasons = await provider.children(show.ref);
          if (seasons.isEmpty) continue;
          final episodes = await provider.children(seasons.first.ref);
          if (episodes.isEmpty) continue;
          withEpisodes++;
          tried++;
          final playback = await provider.playback(episodes.first.ref);
          if (!playback.isPlayable) continue;
          playable++;
          final master = await http.get(playback.streams.first.url.toString());
          expect(master.statusCode, 200);
          expect(master.data.toString(), startsWith('#EXTM3U'));
        } on MediaServerHttpException {
          failed++;
        }
      }
      stdout.writeln(
        '${provider.source.id}: ${shows.totalCount} shows, sampled ${shows.titles.take(_showsToSample).length}, '
        '$withEpisodes with episodes, $playable of $tried first episodes play, $failed site errors',
      );
      expect(playable, greaterThan(0));
    }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
  }
}
