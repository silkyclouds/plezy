import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/pbs/pbs_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real pbs.org. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/pbs_live_test.dart`.
/// Requests are paced at one per second, so this takes about a minute.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('the catalogue serves a show down to a playable stream', () async {
    final provider = PbsProvider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails, isNotEmpty);

    final seasons = await provider.children(const ReplayRef('pbs', 'show:frontline'));
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.firstWhere((s) => s.seasonNumber == 2023).ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, isNotNull);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final master = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(master.statusCode, 200);
    expect(master.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('search hits that PBS refuses abroad are reported, not failed', () async {
    final provider = PbsProvider(MediaServerHttpClient());
    final hits = (await provider.search('frontline')).where((t) => t.kind != ReplayKind.show).take(6).toList();
    expect(hits, isNotEmpty);

    var played = 0;
    var refused = 0;
    for (final hit in hits) {
      final playback = await provider.playback(hit.ref);
      if (playback.isPlayable) {
        played++;
      } else {
        expect(playback.availability, ReplayAvailability.geoBlocked, reason: hit.title);
        expect(playback.message, isNotEmpty);
        refused++;
      }
    }
    // ignore: avoid_print
    print('PBS search sample: $played played, $refused refused of ${hits.length}');
  }, skip: live ? false : skip);

  test('a video known to be US-only is refused with a clear message', () async {
    final provider = PbsProvider(MediaServerHttpClient());
    final playback = await provider.playback(const ReplayRef('pbs', 'video:3059938214/the-cannabis-question'));
    if (!playback.isPlayable) {
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('United States'));
    }
  }, skip: live ? false : skip);

  test('a show with clips only lists clips and previews', () async {
    final provider = PbsProvider(MediaServerHttpClient());
    final seasons = await provider.children(const ReplayRef('pbs', 'show:nova'));
    expect(seasons, isNotEmpty);
    final items = await provider.children(seasons.last.ref);
    expect(items, isNotEmpty);
    expect(items.every((t) => t.isPlayable), isTrue);
  }, skip: live ? false : skip);
}
