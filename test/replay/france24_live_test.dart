import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/france24/france24_language.dart';
import 'package:plezy/replay/providers/france24/france24_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real France 24 catalogue. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/france24_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';
  // Long programmes are read page by page at a polite pace, so one test can take a minute or two.
  const patience = Timeout(Duration(minutes: 4));

  Future<void> expectProgrammeToPlay(France24Provider provider, String query) async {
    final rails = await provider.home();
    expect(rails, isNotEmpty);

    final hits = await provider.search(query);
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
  }

  Future<void> expectFeedClipToPlay(France24Provider provider) async {
    final clips = (await provider.listing('videos')).titles;
    expect(clips, isNotEmpty);
    final playback = await provider.playback(clips.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
  }

  test('a programme leads from its seasons to a playable MP4 file', () async {
    await expectProgrammeToPlay(France24Provider(MediaServerHttpClient()), 'judith');
  }, skip: live ? false : skip, timeout: patience);

  test('a clip of the video feed plays', () async {
    await expectFeedClipToPlay(France24Provider(MediaServerHttpClient()));
  }, skip: live ? false : skip, timeout: patience);

  group('English edition', () {
    France24Provider english() => France24Provider(MediaServerHttpClient(), language: France24Language.english);

    test('a programme leads from its seasons to a playable MP4 file', () async {
      await expectProgrammeToPlay(english(), 'debate');
    }, skip: live ? false : skip, timeout: patience);

    test('a clip of the video feed plays', () async {
      await expectFeedClipToPlay(english());
    }, skip: live ? false : skip, timeout: patience);

    test('an edition with a UUID id opens and plays', () async {
      final provider = english();
      final show = (await provider.search('business')).firstWhere((t) => t.kind == ReplayKind.show);
      final seasons = await provider.children(show.ref);
      final episodes = await provider.children(seasons.last.ref);
      final uuid = episodes.lastWhere((e) => e.ref.nativeId.contains('@'));
      final opened = await provider.title(uuid.ref);
      expect(opened?.ref, uuid.ref);
      final playback = await provider.playback(uuid.ref);
      expect(playback.isPlayable, isTrue, reason: playback.message);
    }, skip: live ? false : skip, timeout: patience);

    test('the YouTube-only programme is not listed', () async {
      final provider = english();
      final all = await provider.listing(replayAllBrowseId);
      expect(all.titles.map((t) => t.title), isNot(contains('The Observers')));
      expect(all.titles.map((t) => t.ref.source).toSet(), {'france24en'});
    }, skip: live ? false : skip, timeout: patience);
  });
}
