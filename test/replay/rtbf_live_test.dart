import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _sampleSize = 40;

/// Talks to the real Auvio. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/rtbf_live_test.dart`.
/// Playback depends on the caller's country: from Belgium most protected titles answer DRM or account.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('a clear magazine goes from search down to an HLS master', () async {
    final provider = RtbfProvider(MediaServerHttpClient());
    final hits = await provider.search('table média');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title.contains('Table'));
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: '${playback.availability} ${playback.message}');
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('a series reports numbered seasons and episodes and says why it cannot play', () async {
    final provider = RtbfProvider(MediaServerHttpClient());
    final show = (await provider.search('ghosts')).firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons.map((s) => s.seasonNumber), everyElement(isNotNull));
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.seasonNumber, seasons.first.seasonNumber);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isFalse);
    expect(playback.availability, isNot(ReplayAvailability.unknown));
  }, skip: live ? false : skip);

  test(
    'a sample of the home and category rows is classified by playback',
    () async {
      final provider = RtbfProvider(MediaServerHttpClient());
      final rails = [...await provider.home()];
      for (final category in (await provider.categories()).take(3)) {
        rails.addAll(await provider.category(category.id));
      }
      final seen = <String>{};
      final sample = [
        for (final title in rails.expand((r) => r.titles))
          if (title.isPlayable && seen.add(title.ref.toString())) title,
      ].take(_sampleSize).toList();
      expect(sample, isNotEmpty);

      final tally = <ReplayAvailability, int>{};
      var predictedRight = 0;
      var predicted = 0;
      for (final title in sample) {
        final playback = await provider.playback(title.ref);
        tally.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
        if (title.availability != ReplayAvailability.playable) {
          predicted++;
          if (title.availability == playback.availability) predictedRight++;
        }
      }
      stdout.writeln('RTBF sample of ${sample.length}: $tally; list predictions right $predictedRight of $predicted');
      expect(tally.values.fold<int>(0, (a, b) => a + b), sample.length);
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: live ? false : skip,
  );

  test('the whole-catalogue listing pages without repeats', () async {
    final provider = RtbfProvider(MediaServerHttpClient());
    final first = await provider.listing('all');
    final second = await provider.listing('all', page: 1);
    expect(first.titles, hasLength(greaterThan(40)));
    expect({
      ...first.titles.map((t) => t.ref),
      ...second.titles.map((t) => t.ref),
    }, hasLength(first.titles.length + second.titles.length));
    expect(first.totalCount, greaterThan(1000));
  }, skip: live ? false : skip);
}
