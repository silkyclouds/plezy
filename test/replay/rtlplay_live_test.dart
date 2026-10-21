import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real RTL Play catalogue. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/rtlplay_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the open catalogue serves a series down to a login-required episode', () async {
    final provider = RtlPlayProvider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails, isNotEmpty);

    final hits = await provider.search('bates motel');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.title, isNot(startsWith('1.')));

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.availability, ReplayAvailability.loginRequired);
    expect(playback.isPlayable, isFalse);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('the full listing, every storefront and a magazine resolve', () async {
    final provider = RtlPlayProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId);
    expect(page.totalCount, greaterThan(100));
    expect(page.titles, hasLength(provider.source.listingPageSize));

    for (final category in await provider.categories()) {
      expect(await provider.category(category.id), isNotEmpty, reason: category.id);
    }

    final news = (await provider.search('rtl info 19')).firstWhere((t) => t.title.contains('19 heures'));
    final seasons = await provider.children(news.ref);
    final episodes = await provider.children(seasons.single.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.airDate, isNotNull);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
