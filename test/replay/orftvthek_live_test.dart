import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real ORF ON API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/orftvthek_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the catalogue serves a show down to a playable stream', () async {
    final provider = OrfTvthekProvider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails, isNotEmpty);

    final hits = await provider.search('zib 1');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'ZIB 1');
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);

    final playback = await provider.playback(episodes.last.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await MediaServerHttpClient().get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('a season of a numbered series lists numbered episodes', () async {
    final provider = OrfTvthekProvider(MediaServerHttpClient());
    final show = (await provider.search('kiwi')).firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons.map((s) => s.seasonNumber), contains(2));
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.map((e) => e.episodeNumber), everyElement(isNotNull));
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('outside Austria an Austria-only programme is reported as blocked', () async {
    final provider = OrfTvthekProvider(MediaServerHttpClient());
    final rails = await provider.home();
    final titles = [for (final rail in rails) ...rail.titles.where((t) => t.isPlayable)];
    final verdicts = await provider.predictAvailability(titles, 'BE');
    final blocked = titles.where((t) => verdicts[t.ref] == ReplayAvailability.geoBlocked).take(2);
    final open = titles.where((t) => verdicts[t.ref] == ReplayAvailability.playable).take(2);
    expect(blocked, isNotEmpty);
    for (final title in blocked) {
      expect((await provider.playback(title.ref)).availability, ReplayAvailability.geoBlocked, reason: title.title);
    }
    for (final title in open) {
      final playback = await provider.playback(title.ref);
      expect(playback.isPlayable, isTrue, reason: '${title.title}: ${playback.message}');
    }
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
