import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/drtv/drtv_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real DR TV API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/drtv_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the catalogue serves a show down to a playable stream', () async {
    final provider = DrtvProvider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails, isNotEmpty);

    final hits = await provider.search('frank kastaniegaarden');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, isNotNull);

    final playback = await provider.playback(episodes.last.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('the whole catalogue pages and sorts open from Denmark-only titles', () async {
    final provider = DrtvProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId);
    expect(page.titles, hasLength(provider.source.listingPageSize));
    expect(page.totalCount, greaterThan(page.titles.length));

    final verdicts = await provider.predictAvailability(page.titles, 'BE');
    final blocked = verdicts.entries.where((e) => e.value == ReplayAvailability.geoBlocked).map((e) => e.key);
    final open = page.titles.where((t) => !verdicts.containsKey(t.ref) && t.isPlayable).take(3).toList();
    expect(blocked, isNotEmpty);

    for (final title in open) {
      final playback = await provider.playback(title.ref);
      expect(playback.isPlayable, isTrue, reason: '${title.title}: ${playback.message}');
    }
    final firstBlocked = page.titles.firstWhere(
      (t) => t.isPlayable && verdicts[t.ref] == ReplayAvailability.geoBlocked,
    );
    expect((await provider.playback(firstBlocked.ref)).availability, ReplayAvailability.geoBlocked);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
