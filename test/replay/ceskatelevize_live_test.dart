import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real iVysílání API. Run with
/// `PLEZY_LIVE_TESTS=1 flutter test test/replay/ceskatelevize_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the open catalogue serves a series down to a playable stream', () async {
    final provider = CeskaTelevizeProvider(MediaServerHttpClient());
    expect(await provider.categories(), isNotEmpty);
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('vyprávěj');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Vyprávěj');
    final seasons = await provider.children(show.ref);
    expect(seasons.first.seasonNumber, 1);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes.first.episodeNumber, 1);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: '${playback.availability} ${playback.message}');
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test(
    'a sample of shows plays or says why, and never throws',
    () async {
      final provider = CeskaTelevizeProvider(MediaServerHttpClient());
      final outcomes = <ReplayAvailability, int>{};
      for (final id in ['3976', '3947', '4003', '4124', '4118']) {
        final titles = (await provider.listing(id)).titles.take(12);
        for (final title in titles) {
          final episodes = title.kind == ReplayKind.movie ? [title] : await _firstEpisodes(provider, title);
          if (episodes.isEmpty) continue;
          final playback = await provider.playback(episodes.first.ref);
          outcomes.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      // ignore: avoid_print
      print('outcomes: $outcomes');
      expect(outcomes[ReplayAvailability.playable], greaterThan(0));
      expect(outcomes.keys, everyElement(isIn(ReplayAvailability.values)));
    },
    skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('the whole-catalogue listing pages through the broadcaster all category', () async {
    final provider = CeskaTelevizeProvider(MediaServerHttpClient());
    final first = await provider.listing('all');
    final second = await provider.listing('all', page: 1);
    expect(first.totalCount, greaterThan(1000));
    expect(first.titles, hasLength(100));
    expect(second.titles.first.ref, isNot(first.titles.first.ref));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}

Future<List<ReplayTitle>> _firstEpisodes(CeskaTelevizeProvider provider, ReplayTitle show) async {
  final seasons = await provider.children(show.ref);
  if (seasons.isEmpty) return const [];
  return provider.children(seasons.first.ref);
}
