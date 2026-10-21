import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/publicsenat/publicsenat_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real site. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/publicsenat_live_test.dart`.
/// It browses only: playback goes through Dailymotion's player metadata, which this suite never requests.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the site serves programmes, seasons and episodes', () async {
    final provider = PublicSenatProvider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails.map((r) => r.id), ['replays', 'programmes']);
    final programmes = rails.last.titles;
    expect(programmes.length, greaterThan(20));

    final show = programmes.firstWhere((t) => t.ref.nativeId == '1000-pays-pour-demain');
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    expect(seasons.every((s) => s.kind == ReplayKind.season), isTrue);
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.durationSeconds, greaterThan(600));

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.streams, isEmpty);
    expect(playback.message, isNotNull);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
