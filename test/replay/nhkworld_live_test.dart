import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/nhkworld/nhkworld_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real NHK WORLD-JAPAN API. Run with `PLEZY_LIVE_TESTS=1 flutter test` on this file.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the open catalogue serves a show down to a playable stream', () async {
    final provider = NhkWorldProvider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails.map((r) => r.id), containsAll(['latest', 'trending']));
    expect(rails.first.titles.first.availableUntil, isNotNull);

    final hits = await provider.search('japanology');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('the whole catalogue lists, and a category narrows it', () async {
    final provider = NhkWorldProvider(MediaServerHttpClient());
    final all = await provider.listing(replayAllBrowseId);
    expect(all.totalCount, greaterThan(100));
    expect(all.titles, hasLength(provider.source.listingPageSize));

    final categories = await provider.categories();
    final kids = await provider.listing(categories.firstWhere((c) => c.title == 'Kids').id);
    expect(kids.totalCount, inInclusiveRange(1, all.totalCount - 1));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
