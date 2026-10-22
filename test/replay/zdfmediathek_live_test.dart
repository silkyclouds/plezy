import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real ZDFmediathek API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/zdfmediathek_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('the open catalogue serves a series down to a playable stream', () async {
    final provider = ZdfMediathekProvider(MediaServerHttpClient());
    expect(await provider.categories(), isNotEmpty);
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('die bergretter');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.seasonNumber, seasons.last.seasonNumber);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('a resized backdrop is served', () async {
    final provider = ZdfMediathekProvider(MediaServerHttpClient());
    final rails = await provider.home();
    final withBackdrop = [for (final r in rails) ...r.titles].firstWhere((t) => t.backdropUrl != null);
    final url = provider.imageUrl(withBackdrop.backdropUrl!, width: 700);
    final response = await MediaServerHttpClient().getBytes(url);
    expect(response, isNotEmpty);
  }, skip: live ? false : skip);

  test('the forecast agrees with what the stream host says', () async {
    final provider = ZdfMediathekProvider(MediaServerHttpClient());
    final rails = await provider.home();
    final titles = [
      for (final r in rails)
        for (final t in r.titles)
          if (t.isPlayable) t,
    ].take(30).toList();
    expect(titles, isNotEmpty);

    final blocked = await provider.predictAvailability(titles, 'BE');
    final tally = <ReplayAvailability, int>{};
    for (final title in titles) {
      final playback = await provider.playback(title.ref);
      tally.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
      if (playback.availability == ReplayAvailability.geoBlocked) {
        expect(blocked[title.ref], ReplayAvailability.geoBlocked, reason: title.title);
      }
      if (blocked.containsKey(title.ref)) {
        expect(playback.availability, ReplayAvailability.geoBlocked, reason: title.title);
      }
    }
    // The tally is the number the maintainer reads from the test log.
    // ignore: avoid_print
    print('ZDF live sample of ${titles.length}: $tally, predicted blocked from BE: ${blocked.length}');
    expect(tally[ReplayAvailability.playable], greaterThan(0));
  }, skip: live ? false : skip);
}
