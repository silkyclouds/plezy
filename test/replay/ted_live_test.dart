import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/ted/ted_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real TED API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/ted_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('the open endpoint serves talks, a search and a playlist down to a stream', () async {
    final http = MediaServerHttpClient();
    final provider = TedProvider(http);
    final rails = await provider.home();
    expect(rails.first.titles, isNotEmpty);

    final page = await provider.listing(replayAllBrowseId, page: 1);
    expect(page.totalCount, greaterThan(5000));
    expect(page.titles, hasLength(20));

    final hits = await provider.search('climate');
    expect(hits, isNotEmpty);

    final talk = page.titles.first;
    final playback = await provider.playback(talk.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    expect(playback.subtitles, isNotEmpty);
    final master = await http.get(playback.streams.first.url.toString());
    expect(master.data.toString(), startsWith('#EXTM3U'));
    final subtitles = await http.get(playback.subtitles.first.url.toString());
    expect(subtitles.data.toString(), startsWith('#EXTM3U'));

    final playlists = await provider.listing('playlists');
    final show = playlists.titles.first;
    final seasons = await provider.children(show.ref);
    expect(seasons.single.kind, ReplayKind.season);
    final episodes = await provider.children(seasons.single.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect((await provider.playback(episodes.first.ref)).isPlayable, isTrue);
    provider.close();
  }, skip: live ? false : skip);

  test('talks from the whole age range resolve to a stream with subtitles', () async {
    final provider = TedProvider(MediaServerHttpClient());
    final sample = <ReplayTitle>[];
    for (final page in [0, 40, 120, 125, 200, 250]) {
      sample.addAll((await provider.listing(replayAllBrowseId, page: page)).titles.take(3));
    }
    var playable = 0;
    final subtitleCounts = <int>[];
    for (final talk in sample) {
      final playback = await provider.playback(talk.ref);
      if (playback.isPlayable) playable++;
      subtitleCounts.add(playback.subtitles.length);
    }
    // ignore: avoid_print
    print('TED live: $playable of ${sample.length} talks playable, subtitle tracks per talk $subtitleCounts');
    expect(playable, sample.length);
    expect(subtitleCounts.any((count) => count > 1), isTrue);
    provider.close();
  }, skip: live ? false : skip);
}
