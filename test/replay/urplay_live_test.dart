// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/urplay/urplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real UR Play API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/urplay_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('the open catalogue serves a show down to a playable stream', () async {
    final provider = UrPlayProvider(MediaServerHttpClient());
    expect(await provider.categories(), isNotEmpty);
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('Lässugen');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Lässugen');
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    expect(seasons.last.seasonNumber, greaterThan(0));
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.showRef, show.ref);

    final detail = await provider.title(episodes.first.ref);
    expect(detail!.showRef, show.ref);
    expect(detail.seasonRef, seasons.last.ref);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('the forecast agrees with playback on a sample of programmes', () async {
    final provider = UrPlayProvider(MediaServerHttpClient());
    final sample = [
      for (final query in ['natur', 'djur', 'resa'])
        ...(await provider.search(query)).where((t) => t.isPlayable).take(8),
    ];
    expect(sample, isNotEmpty);

    final verdicts = await provider.predictAvailability(sample, 'BE');
    var playable = 0;
    var geoBlocked = 0;
    for (final title in sample) {
      final playback = await provider.playback(title.ref);
      expect(
        playback.availability,
        anyOf(ReplayAvailability.playable, ReplayAvailability.geoBlocked),
        reason: '${title.ref}: ${playback.message}',
      );
      if (playback.isPlayable) playable++;
      if (playback.availability == ReplayAvailability.geoBlocked) geoBlocked++;
      expect(verdicts[title.ref], playback.availability, reason: '${title.ref} ${title.title}');
    }
    print('urplay live sample: ${sample.length} programmes, $playable play, $geoBlocked Sweden-only');
    expect(playable, greaterThan(0));
  }, skip: live ? false : skip);

  test('a Sweden-only show is greyed out before it is opened', () async {
    final provider = UrPlayProvider(MediaServerHttpClient());
    final page = await provider.listing('series:Reseprogram');
    expect(page.titles, isNotEmpty);
    final verdicts = await provider.predictAvailability(page.titles, 'BE');
    print(
      'urplay live Reseprogram shows: ${page.titles.length}, '
      '${verdicts.values.where((v) => v == ReplayAvailability.geoBlocked).length} Sweden-only',
    );
    expect(verdicts.values, contains(ReplayAvailability.geoBlocked));
  }, skip: live ? false : skip);
}
