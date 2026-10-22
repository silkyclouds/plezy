import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/svtplay/svtplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real SVT Play API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/svtplay_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('a worldwide series goes down to a playable HLS master', () async {
    final provider = SvtPlayProvider(MediaServerHttpClient());
    expect(await provider.categories(), isNotEmpty);
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('fixa rummet');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Fixa rummet');
    final seasons = await provider.children(show.ref);
    expect(seasons.length, greaterThan(5));
    expect(seasons.first.seasonNumber, 1);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, isNotNull);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('the news show hides announced episodes and plays the latest one', () async {
    final provider = SvtPlayProvider(MediaServerHttpClient());
    final seasons = await provider.children(const ReplayRef('svtplay', 'eoVPJNz'));
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    final now = DateTime.now().toUtc();
    expect(episodes.every((e) => e.airDate == null || !e.airDate!.isAfter(now)), isTrue);

    final playback = await provider.playback(episodes.last.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
  }, skip: live ? false : skip);

  test('the catalogue flags Sweden-only and protected titles for a viewer abroad', () async {
    final provider = SvtPlayProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId);
    expect(page.totalCount, greaterThan(1000));
    final verdicts = await provider.predictAvailability(page.titles, 'BE');
    final blocked = verdicts.values.where((v) => v == ReplayAvailability.geoBlocked);
    expect(blocked, isNotEmpty);
    expect(await provider.predictAvailability(page.titles, 'SE'), isNot(containsValue(ReplayAvailability.geoBlocked)));
  }, skip: live ? false : skip);

  test('a Sweden-only film is refused outside Sweden and a protected one is never fetched', () async {
    final provider = SvtPlayProvider(MediaServerHttpClient());
    final swedenOnly = await provider.playback(const ReplayRef('svtplay', 'K1B4ab6'));
    expect(swedenOnly.isPlayable, isFalse);
    expect(swedenOnly.availability, anyOf(ReplayAvailability.geoBlocked, ReplayAvailability.expired));

    final protected = await provider.playback(const ReplayRef('svtplay', 'jpWEZDk'));
    expect(protected.availability, anyOf(ReplayAvailability.drmProtected, ReplayAvailability.expired));
    expect(protected.streams, isEmpty);
  }, skip: live ? false : skip);
}
