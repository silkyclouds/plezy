import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/srfplay/srfplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real SRF Play API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/srfplay_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  Future<void> expectMasterPlaylist(Uri url) async {
    final response = await MediaServerHttpClient().get(url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }

  test('a numbered documentary series serves seasons down to a stream', () async {
    final provider = SrfPlayProvider(MediaServerHttpClient());
    expect(await provider.categories(), isNotEmpty);
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('Hoch hinaus');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'DOK – Hoch hinaus');
    final seasons = await provider.children(show.ref);
    final numbered = seasons.where((s) => (s.seasonNumber ?? 0) > 0).toList();
    expect(numbered, isNotEmpty);
    final episodes = await provider.children(numbered.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, isNotNull);

    final playable = episodes.firstWhere((e) => e.availability == ReplayAvailability.playable);
    final playback = await provider.playback(playable.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    await expectMasterPlaylist(playback.streams.first.url);
  }, skip: live ? false : skip);

  test('the daily news is browsed by year and plays', () async {
    final provider = SrfPlayProvider(MediaServerHttpClient());
    final seasons = await provider.children(const ReplayRef('srfplay', 'show:ff969c14-c5a7-44ab-ab72-14d4c9e427a9'));
    expect(seasons.length, greaterThan(10));
    final recent = await provider.children(seasons.last.ref);
    expect(recent, isNotEmpty);
    final playback = await provider.playback(recent.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    await expectMasterPlaylist(playback.streams.first.url);
  }, skip: live ? false : skip);

  test('the catalogue lists shows and flags what is closed abroad', () async {
    final provider = SrfPlayProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId);
    expect(page.totalCount, greaterThan(150));
    expect(page.titles.map((t) => t.title), isNot(contains('Kassensturz in Gebärdensprache')));

    final hits = await provider.search('Kassensturz');
    final episodes = hits.where((t) => t.kind == ReplayKind.episode).toList();
    expect(episodes, isNotEmpty);
    final verdicts = await provider.predictAvailability(episodes, 'BE');
    expect(verdicts.values.toSet().difference({ReplayAvailability.geoBlocked}), isEmpty);
  }, skip: live ? false : skip);

  test('a blocked programme is reported, not played', () async {
    final provider = SrfPlayProvider(MediaServerHttpClient());
    final blocked = await provider.playback(const ReplayRef('srfplay', 'video:f28c7b5e-d2ef-4ff9-bd6a-73fe15ec29c3'));
    expect(blocked.isPlayable, isFalse);
    expect(blocked.availability, anyOf(ReplayAvailability.geoBlocked, ReplayAvailability.expired));
  }, skip: live ? false : skip);
}
