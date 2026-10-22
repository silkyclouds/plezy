import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/nfb/nfb_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real nfb.ca. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/nfb_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the home page, search and a film play down to a clear HLS master', () async {
    final http = MediaServerHttpClient();
    final provider = NfbProvider(http);
    final rails = await provider.home();
    expect(rails, isNotEmpty);

    final hits = await provider.search('ryan');
    final ryan = hits.firstWhere((t) => t.ref.nativeId == 'ryan');
    expect(ryan.kind, ReplayKind.movie);
    expect(ryan.posterUrl, isNotNull);
    expect((await provider.title(ryan.ref))!.year, 2004);

    final playback = await provider.playback(ryan.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final master = await http.get(playback.streams.first.url.toString());
    expect(master.statusCode, 200);
    expect(master.data.toString(), startsWith('#EXTM3U'));
    expect(master.data.toString(), isNot(contains('#EXT-X-KEY')));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('a series opens down to a playable or honestly blocked episode', () async {
    final provider = NfbProvider(MediaServerHttpClient());
    final shows = (await provider.listing('series')).titles;
    expect(shows, isNotEmpty);
    final show = shows.firstWhere((s) => s.ref.nativeId == 's/the-great-list-of-everything-series');
    final seasons = await provider.children(show.ref);
    expect(seasons.map((s) => s.seasonNumber), [1, 2]);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, hasLength(13));
    expect(episodes.first.episodeNumber, 1);

    final detail = await provider.title(episodes.first.ref);
    expect(detail!.showRef, show.ref);
    expect(detail.seasonRef, seasons.first.ref);
    expect(detail.durationSeconds, greaterThan(0));

    final playback = await provider.playback(episodes.first.ref);
    expect(
      playback.isPlayable || playback.availability == ReplayAvailability.geoBlocked,
      isTrue,
      reason: playback.message,
    );
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('listed films play unless the list already marks them blocked', () async {
    final provider = NfbProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId, page: 40);
    expect(page.titles, isNotEmpty);
    expect(page.totalCount, greaterThan(3000));

    final outcomes = <ReplayAvailability, int>{};
    var disagreements = 0;
    for (final title in page.titles.take(10)) {
      final playback = await provider.playback(ReplayRef('nfb', title.ref.nativeId));
      outcomes.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
      final predicted = title.availability;
      if (playback.isPlayable != (predicted == ReplayAvailability.playable)) disagreements++;
    }
    // ignore: avoid_print
    print('NFB live: playback outcomes $outcomes, list/playback disagreements $disagreements of 10');
    expect(disagreements, 0);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
