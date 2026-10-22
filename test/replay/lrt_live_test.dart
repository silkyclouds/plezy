import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/lrt/lrt_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real lrt.lt. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/lrt_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the landing rows lead to a programme, a season and a playable stream', () async {
    final http = MediaServerHttpClient();
    final provider = LrtProvider(http);
    final rails = await provider.home();
    expect(rails, isNotEmpty);
    expect(rails.first.titles, isNotEmpty);

    final index = await provider.listing('all');
    expect(index.totalCount, greaterThan(1000));

    final hits = await provider.search('zinios');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.every((e) => e.kind == ReplayKind.episode), isTrue);

    final playback = await provider.playback(episodes.last.ref);
    expect(playback.isPlayable, isTrue, reason: '${playback.availability} ${playback.message}');
    final master = await http.get(playback.streams.first.url.toString());
    expect(master.statusCode, 200);
    expect(master.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('a random sample of programmes reports each outcome', () async {
    final provider = LrtProvider(MediaServerHttpClient());
    final programmes = (await provider.listing('all')).titles;
    var played = 0;
    var geoBlocked = 0;
    var expired = 0;
    var other = 0;
    final odd = <String>[];
    final sample = [for (var i = 0; i < programmes.length && i < 40; i += 1) programmes[(i * 7) % programmes.length]];
    for (final programme in sample.take(15)) {
      final seasons = await provider.children(programme.ref);
      if (seasons.isEmpty) continue;
      final episodes = await provider.children(seasons.last.ref);
      if (episodes.isEmpty) continue;
      final playback = await provider.playback(episodes.last.ref);
      if (playback.isPlayable) {
        played++;
      } else if (playback.availability == ReplayAvailability.geoBlocked) {
        geoBlocked++;
      } else if (playback.availability == ReplayAvailability.expired) {
        expired++;
      } else {
        other++;
        odd.add('${episodes.last.ref} ${playback.availability} ${playback.message}');
      }
    }
    // ignore: avoid_print
    print('LRT sample: played=$played geoBlocked=$geoBlocked expired=$expired other=$other $odd');
    expect(played, greaterThan(0));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
