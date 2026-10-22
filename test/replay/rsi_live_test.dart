import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/rsi/rsi_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real RSI Play API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/rsi_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  Future<void> expectMasterPlaylist(Uri url) async {
    final response = await MediaServerHttpClient().get(url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }

  test('the news magazine serves years down to a stream', () async {
    final provider = RsiProvider(MediaServerHttpClient());
    expect(await provider.categories(), isNotEmpty);
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('Il Quotidiano');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Il Quotidiano');
    final seasons = await provider.children(show.ref);
    expect(seasons.length, greaterThan(5));
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);

    final playable = episodes.firstWhere((e) => e.availability == ReplayAvailability.playable);
    final playback = await provider.playback(playable.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    await expectMasterPlaylist(playback.streams.first.url);
  }, skip: live ? false : skip);

  test('a numbered series is closed abroad and says so', () async {
    final provider = RsiProvider(MediaServerHttpClient());
    final seasons = await provider.children(const ReplayRef('rsi', 'show:2649987'));
    expect(seasons.single.title, 'Stagione 1');
    final episodes = await provider.children(seasons.single.ref);
    expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6, 7]);
    expect(episodes.first.title, 'La selezione');

    final verdicts = await provider.predictAvailability([seasons.single, ...episodes], 'BE');
    expect(verdicts.values.toSet(), {ReplayAvailability.geoBlocked});
    final playback = await provider.playback(episodes.first.ref);
    expect(playback.availability, ReplayAvailability.geoBlocked);
    expect(playback.streams, isEmpty);
  }, skip: live ? false : skip);

  test('the catalogue hides sign-language copies', () async {
    final provider = RsiProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId);
    expect(page.totalCount, greaterThan(250));
    expect(page.titles.map((t) => t.title), isNot(contains('Il Quotidiano LIS')));
  }, skip: live ? false : skip);
}
