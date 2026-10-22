import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/3cat/threecat_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real 3Cat API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/threecat_live_test.dart` from a
/// country other than Spain: it expects Spain-only titles to be refused.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('a worldwide show goes down to a stream the host serves', () async {
    final provider = ThreeCatProvider(MediaServerHttpClient());
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('patrimonis');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Patrimonis');
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, isNotNull);
    expect(episodes.first.seasonNumber, seasons.first.seasonNumber);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final manifest = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(manifest.statusCode, 200);
    expect(manifest.data.toString(), contains('<MPD'));
    expect(manifest.data.toString(), isNot(contains('ContentProtection')));
  }, skip: live ? false : skip);

  test('a Spain-only series is flagged in the list and refused on play', () async {
    final provider = ThreeCatProvider(MediaServerHttpClient());
    final show = (await provider.search('merlí')).firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Merlí');
    final seasons = await provider.children(show.ref);
    expect(seasons.map((s) => s.seasonNumber), containsAll([1, 2, 3]));
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes.length, greaterThan(5));

    final verdicts = await provider.predictAvailability(episodes, 'BE');
    expect(verdicts[episodes.first.ref], ReplayAvailability.geoBlocked);
    final playback = await provider.playback(episodes.first.ref);
    expect(playback.availability, ReplayAvailability.geoBlocked);
    expect(playback.message, isNotNull);
  }, skip: live ? false : skip);

  test(
    'a sample of the catalogue plays or is refused as forecast',
    () async {
      final provider = ThreeCatProvider(MediaServerHttpClient());
      final rails = await provider.home();
      final shows = [
        for (final rail in rails)
          for (final title in rail.titles)
            if (title.kind == ReplayKind.show) title,
      ];
      final sampled = {for (final s in shows) s.ref: s}.values.take(14).toList();
      var playable = 0;
      var blocked = 0;
      var other = 0;
      var episodesSeen = 0;
      for (final show in sampled) {
        final seasons = await provider.children(show.ref);
        if (seasons.isEmpty) continue;
        final episodes = (await provider.children(seasons.first.ref)).take(3).toList();
        episodesSeen += episodes.length;
        final verdicts = await provider.predictAvailability(episodes, 'BE');
        for (final episode in episodes) {
          final playback = await provider.playback(episode.ref);
          final forecast = verdicts[episode.ref] ?? ReplayAvailability.playable;
          if (playback.isPlayable) {
            playable++;
          } else if (playback.availability == ReplayAvailability.geoBlocked) {
            blocked++;
          } else {
            other++;
          }
          expect(playback.availability, forecast, reason: '${show.title} ${episode.title}');
        }
      }
      stdout.writeln(
        '3cat sample: ${sampled.length} shows, $episodesSeen episodes, $playable playable, $blocked Spain-only, $other other',
      );
      expect(episodesSeen, greaterThan(0));
      expect(other, 0);
    },
    skip: live ? false : skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('the A-Z page lists the whole catalogue', () async {
    final provider = ThreeCatProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId);
    expect(page.totalCount, greaterThan(500));
    expect(page.titles, hasLength(provider.source.listingPageSize));
    final later = await provider.listing(replayAllBrowseId, page: 3);
    expect(later.titles, isNotEmpty);
    final related = await provider.listing('q:tot?frontal=trescat-tresplseri-prodesweb');
    expect(related.titles, isNotEmpty);
  }, skip: live ? false : skip);
}
