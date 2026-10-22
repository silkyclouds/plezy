import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/screens/replay/replay_blocking.dart';

import '../../test_helpers/media_items.dart';
import 'replay_detail_fixtures.dart';

bool _nobody(String sourceId) => false;
bool _everybody(String sourceId) => true;

void main() {
  group('replayItemBlocks', () {
    test('a playable title is not blocked', () {
      expect(replayItemBlocks(replayItem('arte:1', ReplayAvailability.playable), _nobody), isFalse);
    });

    test('a title of another backend is never blocked', () {
      expect(replayItemBlocks(testMediaItem(id: 'plex-1'), _nobody), isFalse);
    });

    test('a geo-blocked title is blocked whoever is signed in', () {
      expect(replayItemBlocks(replayItem('francetv:1', ReplayAvailability.geoBlocked), _everybody), isTrue);
    });

    test('an account-only title is blocked until the viewer signs in', () {
      final item = replayItem('rtlplay:1', ReplayAvailability.loginRequired);
      expect(replayItemBlocks(item, _nobody), isTrue);
      expect(replayItemBlocks(item, (id) => id == 'rtlplay'), isFalse);
    });
  });

  group('replayBlockerOf', () {
    final blocked = replayItem('francetv:e1', ReplayAvailability.geoBlocked);
    final playable = replayItem('francetv:e2', ReplayAvailability.playable);
    final show = replayItem('francetv:s', ReplayAvailability.playable, kind: MediaKind.show);

    test('a blocked page is its own blocker', () {
      final page = replayItem('francetv:s', ReplayAvailability.geoBlocked, kind: MediaKind.show);
      expect(replayBlockerOf(page, [playable], _nobody), same(page));
    });

    test('a show whose loaded episodes are all blocked is blocked by its first episode', () {
      expect(replayBlockerOf(show, [blocked, blocked], _nobody), same(blocked));
    });

    test('a show with one playable episode keeps its usual page', () {
      expect(replayBlockerOf(show, [blocked, playable], _nobody), isNull);
    });

    test('a show with no episodes loaded yet keeps its usual page', () {
      expect(replayBlockerOf(show, const [], _nobody), isNull);
    });

    test('an episode page ignores the episodes list', () {
      final page = replayItem('francetv:e3', ReplayAvailability.playable);
      expect(replayBlockerOf(page, [blocked], _nobody), isNull);
    });
  });
}
