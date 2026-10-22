import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import 'rtveplay_test_support.dart';

/// Talks to the real RTVE API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/rtveplay_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('a numbered show goes from search to a playable HLS master', () async {
    final provider = RtvePlayProvider(MediaServerHttpClient());
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('mañaneros 360');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    expect(seasons.map((s) => s.seasonNumber), isNot(contains(null)));

    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.every((e) => e.episodeNumber != null), isTrue);

    final playback = await provider.playback(episodes.last.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('recorded Spain-only videos are refused as geoblocked', () async {
    final provider = RtvePlayProvider(MediaServerHttpClient());
    for (final id in ['v16859989', 'v1888987']) {
      final playback = await provider.playback(rtveRef(id));
      expect(playback.availability, ReplayAvailability.geoBlocked, reason: id);
      expect(playback.streams, isEmpty);
    }
  }, skip: live ? false : skip);

  test(
    'a sample of programmes plays or is refused, never fails',
    () async {
      final provider = RtvePlayProvider(MediaServerHttpClient());
      final shows = <ReplayTitle>[];
      for (final page in [0, 10, 30, 60]) {
        shows.addAll((await provider.listing(replayAllBrowseId, page: page)).titles.take(5));
      }
      final outcomes = <ReplayAvailability, int>{};
      var withEpisodes = 0;
      for (final show in shows) {
        final seasons = await provider.children(show.ref);
        if (seasons.isEmpty) continue;
        final episodes = await provider.children(seasons.first.ref);
        if (episodes.isEmpty) continue;
        withEpisodes++;
        final playback = await provider.playback(episodes.first.ref);
        outcomes.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
        // ignore: avoid_print
        print('${show.title}: ${playback.availability.name} (${episodes.length} episodes)');
      }
      // ignore: avoid_print
      print('sampled ${shows.length} programmes, $withEpisodes with episodes: $outcomes');
      expect(outcomes.keys.toSet().difference({ReplayAvailability.playable, ReplayAvailability.geoBlocked}), isEmpty);
      expect(outcomes[ReplayAvailability.playable] ?? 0, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: live ? false : skip,
  );
}
