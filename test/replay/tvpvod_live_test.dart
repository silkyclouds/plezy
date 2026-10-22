import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/tvpvod/tvpvod_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real TVP VOD API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/tvpvod_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('the open catalogue serves a series down to a playable stream', () async {
    final provider = TvpVodProvider(MediaServerHttpClient());
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('ranczo');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Ranczo');
    final seasons = await provider.children(show.ref);
    expect(seasons.map((s) => s.seasonNumber), containsAllInOrder([1, 2, 3]));
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.title, 'Spadek');

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: '${playback.availability} ${playback.message}');
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('every title predicted blocked is refused, and the rest are sampled', () async {
    final provider = TvpVodProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId, page: 1);
    final sample = page.titles.take(12).toList();
    final verdicts = await provider.predictAvailability(sample, 'BE');

    var played = 0;
    var refused = 0;
    for (final title in sample) {
      final playback = await provider.playback(await _firstPlayable(provider, title));
      if (playback.isPlayable) played++;
      if (playback.availability == ReplayAvailability.geoBlocked) refused++;
      if (verdicts.containsKey(title.ref)) {
        expect(playback.availability, ReplayAvailability.geoBlocked, reason: 'predicted blocked: ${title.title}');
      }
    }
    // ignore: avoid_print
    print(
      'TVPVOD sample: ${sample.length} titles, $played played, $refused refused, ${verdicts.length} predicted',
    );
    expect(played + refused, greaterThan(0));
  }, skip: live ? false : skip, timeout: const Timeout(Duration(minutes: 3)));
}

/// A show cannot be played: its first episode stands in for it.
Future<ReplayRef> _firstPlayable(ReplayProvider provider, ReplayTitle title) async {
  if (title.kind != ReplayKind.show) return title.ref;
  final seasons = await provider.children(title.ref);
  if (seasons.isEmpty) return title.ref;
  final episodes = await provider.children(seasons.first.ref);
  return episodes.isEmpty ? title.ref : episodes.first.ref;
}
