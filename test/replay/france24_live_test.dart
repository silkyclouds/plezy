import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/france24/france24_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real France 24 catalogue. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/france24_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('a programme leads from its seasons to a playable MP4 file', () async {
    final provider = France24Provider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails, isNotEmpty);

    final hits = await provider.search('judith');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.last.seasonNumber, seasons.last.seasonNumber);

    final playback = await provider.playback(episodes.last.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final ranged = await MediaServerHttpClient().get(
      playback.streams.first.url.toString(),
      headers: {'Range': 'bytes=0-0'},
    );
    expect(ranged.statusCode, 206);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');

  test('a clip of the video feed plays', () async {
    final provider = France24Provider(MediaServerHttpClient());
    final clips = (await provider.listing('videos')).titles;
    expect(clips, isNotEmpty);
    final playback = await provider.playback(clips.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
