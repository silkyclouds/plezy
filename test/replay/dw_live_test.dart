import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_playback.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/dw/dw_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real DW endpoints. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/dw_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skipReason = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('home, programmes and latest videos are served', () async {
    final provider = DwProvider(MediaServerHttpClient());
    final home = await provider.home();
    expect(home, isNotEmpty);
    final programmes = await provider.listing(replayAllBrowseId);
    expect(programmes.totalCount, greaterThan(20));
    expect(programmes.titles.map((t) => t.title), contains('DocFilm'));
    final latest = await provider.listing('latest');
    expect(latest.titles, hasLength(30));
    expect(latest.totalCount, greaterThan(1000));
  }, skip: live ? false : skipReason);

  test('a programme opens down to episodes that play', () async {
    final http = MediaServerHttpClient();
    final provider = DwProvider(http);
    final hits = await provider.search('docfilm');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'DocFilm');
    final seasons = await provider.children(show.ref);
    expect(seasons.length, greaterThan(5));
    expect(seasons.last.childCount, greaterThan(0));
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.every((e) => e.seasonNumber == seasons.last.seasonNumber), isTrue);

    final outcomes = <ReplayAvailability, int>{};
    var withSubtitles = 0;
    ReplayPlayback? played;
    for (final episode in episodes.reversed.take(8)) {
      final playback = await provider.playback(episode.ref);
      outcomes[playback.availability] = (outcomes[playback.availability] ?? 0) + 1;
      if (playback.subtitles.isNotEmpty) withSubtitles++;
      if (playback.isPlayable) played ??= playback;
    }
    // ignore: avoid_print
    print('DW playback outcomes: $outcomes, with subtitles: $withSubtitles');
    // ignore: avoid_print
    print('DW seasons: ${seasons.length}, newest season listed: ${episodes.length}');
    expect(played, isNotNull);
    final master = await http.get(played!.streams.first.url.toString());
    expect(master.statusCode, 200);
    expect(master.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skipReason);

  test('search finds videos and a clip plays', () async {
    final http = MediaServerHttpClient();
    final provider = DwProvider(http);
    final hits = await provider.search('climate');
    expect(hits, isNotEmpty);
    final video = hits.firstWhere((t) => t.isPlayable);
    final playback = await provider.playback(video.ref);
    // ignore: avoid_print
    print('DW search hit ${video.ref} (${video.kind.name}) -> ${playback.availability.name}');
    expect(playback.availability, isIn([ReplayAvailability.playable, ReplayAvailability.expired]));
  }, skip: live ? false : skipReason);
}
