import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/rtsplay/rtsplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real RTS Play API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/rtsplay_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('the open catalogue serves a series down to a playable stream', () async {
    final provider = RtsPlayProvider(MediaServerHttpClient());
    expect(await provider.categories(), isNotEmpty);
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('bye bye la suisse');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons.length, greaterThan(5));
    final latest = seasons.where((s) => s.seasonNumber != 0).last;
    final episodes = await provider.children(latest.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, isNotNull);

    final playable = episodes.firstWhere((e) => e.availability == ReplayAvailability.playable);
    final playback = await provider.playback(playable.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('a long daily show is browsed by year and plays', () async {
    final provider = RtsPlayProvider(MediaServerHttpClient());
    final seasons = await provider.children(const ReplayRef('rtsplay', 'show:105932'));
    expect(seasons.length, greaterThan(10));
    final recent = await provider.children(seasons.last.ref);
    expect(recent, isNotEmpty);
    final old = await provider.children(seasons[seasons.length ~/ 2].ref);
    expect(old, isNotEmpty);
    expect(old.first.seasonNumber, seasons[seasons.length ~/ 2].seasonNumber);

    final playback = await provider.playback(recent.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
  }, skip: live ? false : skip);

  test('blocked and protected programmes are reported, not played', () async {
    final provider = RtsPlayProvider(MediaServerHttpClient());
    final blocked = await provider.playback(const ReplayRef('rtsplay', 'video:0d9865f7-9973-3886-b61c-89a5a98c430e'));
    expect(blocked.isPlayable, isFalse);
    expect(blocked.availability, anyOf(ReplayAvailability.geoBlocked, ReplayAvailability.expired));

    final drm = await provider.playback(const ReplayRef('rtsplay', 'video:77664424-7f00-3e17-977e-9887e03ab687'));
    expect(drm.availability, ReplayAvailability.drmProtected);
    expect(drm.streams, isEmpty);
  }, skip: live ? false : skip);
}
