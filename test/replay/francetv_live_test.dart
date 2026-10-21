import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_playback.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/francetv/francetv_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real France.tv API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/francetv_live_test.dart`.
///
/// Rights depend on where the test runs: most replays are refused outside France, so the test asserts that a
/// refusal is reported as one, and that whatever does play really serves a manifest.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skipReason = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('home and a category list shows and videos', () async {
    final provider = FranceTvProvider(MediaServerHttpClient());
    final home = await provider.home();
    expect(home, isNotEmpty);
    final category = await provider.category('series-et-fictions');
    expect(category.expand((r) => r.titles), isNotEmpty);
    final page = await provider.listing('series-et-fictions');
    expect(page.titles, isNotEmpty);
    expect(page.titles.every((t) => t.kind == ReplayKind.show), isTrue);
  }, skip: live ? false : skipReason);

  test('a series opens down to episodes and a rights verdict', () async {
    final provider = FranceTvProvider(MediaServerHttpClient());
    final hits = await provider.search('dix pour cent');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    expect(show.title.toLowerCase(), 'dix pour cent');

    final seasons = await provider.children(show.ref);
    expect(seasons.map((s) => s.seasonNumber), orderedEquals([1, 2, 3, 4]));
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.seasonRef, seasons.first.ref);

    final playback = await provider.playback(episodes.first.ref);
    if (!playback.isPlayable) {
      expect(playback.availability, isIn([ReplayAvailability.geoBlocked, ReplayAvailability.expired]));
      expect(playback.message, isNotEmpty);
    }
  }, skip: live ? false : skipReason);

  test('the evening news plays down to a served manifest', () async {
    final http = MediaServerHttpClient();
    final provider = FranceTvProvider(http);
    final hits = await provider.search('journal 20h00');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title.toLowerCase().contains('20h00'));
    final seasons = await provider.children(show.ref);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);

    final outcomes = <ReplayAvailability, int>{};
    ReplayPlayback? played;
    for (final episode in episodes.take(8)) {
      final playback = await provider.playback(episode.ref);
      outcomes.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
      if (playback.isPlayable) played ??= playback;
    }
    stdout.writeln('journal 20h00 outcomes: $outcomes');
    expect(played, isNotNull, reason: 'none of the first 8 editions played: $outcomes');
    final response = await http.get(played!.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skipReason);
}
