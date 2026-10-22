import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real NRK API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/nrktv_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('a series opens down to a stream, and Norway-only items say so', () async {
    final provider = NrkTvProvider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails, isNotEmpty);

    final show = (await provider.search('humoretaten')).firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes.first.episodeNumber, 1);

    final playable = episodes.where((e) => e.availability == ReplayAvailability.playable);
    final playback = await provider.playback(playable.last.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('the index, news and a blocked programme behave as recorded', () async {
    final provider = NrkTvProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId);
    expect(page.titles, hasLength(provider.source.listingPageSize));

    final news = await provider.children(const ReplayRef('nrktv', 'series/dagsrevyen'));
    final editions = await provider.children(news.last.ref);
    final played = await provider.playback(
      editions.firstWhere((e) => e.availability == ReplayAvailability.playable).ref,
    );
    expect([ReplayAvailability.playable, ReplayAvailability.geoBlocked], contains(played.availability));

    final blocked = await provider.playback(const ReplayRef('nrktv', 'program/KMNO10057925'));
    expect(blocked.availability, ReplayAvailability.geoBlocked);
    final verdicts = await provider.predictAvailability([
      ReplayTitle(ref: const ReplayRef('nrktv', 'program/KMNO10057925'), kind: ReplayKind.movie, title: 'x'),
    ], 'BE');
    expect(verdicts.values.single, ReplayAvailability.geoBlocked);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
