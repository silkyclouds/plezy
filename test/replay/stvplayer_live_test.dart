import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/stvplayer/stvplayer_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real STV Player API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/stvplayer_live_test.dart`.
///
/// Outside the UK the catalogue works and Brightcove answers geo-blocked, so playback may be either verdict.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the catalogue serves a series and a daily show down to a playback verdict', () async {
    final provider = StvPlayerProvider(MediaServerHttpClient());

    final categories = await provider.categories();
    expect(categories, isNotEmpty);
    final rails = await provider.home();
    expect(rails.map((r) => r.id), containsAll(['_recent', '_viewed', '_popular']));
    final category = await provider.category(categories.first.id);
    expect(category, isNotEmpty);
    final page = await provider.listing(replayAllBrowseId, page: 1);
    expect(page.titles, hasLength(provider.source.listingPageSize));
    expect(page.totalCount, greaterThan(500));

    final hits = await provider.search('taggart');
    final series = hits.firstWhere((t) => t.ref.nativeId == 'taggart');
    final seasons = await provider.children(series.ref);
    expect(seasons.length, greaterThan(20));
    expect(seasons.first.seasonNumber, 1);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.seasonNumber, 1);

    final daily = (await provider.search('scotland tonight')).first;
    final dailySeasons = await provider.children(daily.ref);
    expect(dailySeasons, hasLength(1));
    final dailyEpisodes = await provider.children(dailySeasons.single.ref);
    expect(dailyEpisodes, isNotEmpty);
    expect(dailyEpisodes.first.airDate, isNotNull);

    final verdicts = await (provider as ReplayAvailabilityPredictor).predictAvailability(episodes, 'BE');
    expect(verdicts.values.toSet(), {ReplayAvailability.geoBlocked});

    final playback = await provider.playback(episodes.first.ref);
    // ignore: avoid_print
    print('episodes ${episodes.length}, daily ${dailyEpisodes.length}, playback ${playback.availability.name}');
    expect([ReplayAvailability.geoBlocked, ReplayAvailability.playable], contains(playback.availability));
    if (playback.isPlayable) {
      final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
      expect(response.statusCode, 200);
    }
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
