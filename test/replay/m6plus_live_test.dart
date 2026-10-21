import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real M6+ API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/m6plus_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('the open catalogue serves a series down to a protected episode', () async {
    final provider = M6plusProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId);
    expect(page.titles, hasLength(greaterThan(50)));

    final hits = await provider.search('pretty little liars');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons.length, greaterThan(3));
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes.first.episodeNumber, 1);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isFalse);
    expect(playback.availability, ReplayAvailability.drmProtected);
  }, skip: live ? false : skip);

  test('a clear extract plays from a country its rights allow', () async {
    final provider = M6plusProvider(MediaServerHttpClient());
    final seasons = await provider.children((await provider.search('traitres nouvelle')).first.ref);
    final extracts = seasons.firstWhere((s) => s.title == 'Extraits et bonus');
    final clips = await provider.children(extracts.ref);
    expect(clips, isNotEmpty);

    final playback = await provider.playback(clips.first.ref);
    expect(
      [ReplayAvailability.playable, ReplayAvailability.geoBlocked],
      contains(playback.availability),
      reason: playback.message,
    );
    if (playback.isPlayable) {
      final manifest = await MediaServerHttpClient().get(playback.streams.first.url.toString());
      expect(manifest.statusCode, 200);
      expect(manifest.data.toString(), startsWith('#EXTM3U'));
    }
  }, skip: live ? false : skip);

  test('a podcast resolves to an audio file', () async {
    final provider = M6plusProvider(MediaServerHttpClient());
    final show = (await provider.search('1001 vies')).first;
    final season = (await provider.children(show.ref)).single;
    final episode = (await provider.children(season.ref)).first;
    final playback = await provider.playback(episode.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    expect(playback.streams.single.url.path, endsWith('.mp3'));
  }, skip: live ? false : skip);
}
