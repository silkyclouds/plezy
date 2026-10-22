import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/srg/srg_geo.dart';
import 'package:plezy/replay/providers/srg/srg_ids.dart';
import 'package:plezy/replay/providers/srg/srg_images.dart';
import 'package:plezy/replay/providers/srg/srg_numbering.dart';
import 'package:plezy/replay/providers/srg/srg_playback.dart';
import 'package:plezy/replay/providers/srg/srg_show_filter.dart';
import 'package:plezy/replay/providers/srg/srg_unit.dart';

import 'srg_test_support.dart';

class _NoImages implements SrgImageResizer {
  const _NoImages();

  @override
  bool owns(String reference) => false;

  @override
  String url(String reference, {int? width, int? height}) => reference;
}

/// A made-up business unit, so the shared code is exercised without any real broadcaster's settings.
final _unit = SrgUnit(
  businessUnit: 'xx',
  sourceId: 'xxplay',
  name: 'XX Play',
  language: 'rm',
  originalLabel: 'RM',
  texts: const SrgTexts(
    latest: 'a',
    trending: 'b',
    mostClicked: 'c',
    soonExpiring: 'd',
    season: 'Sez',
    extras: 'Extra',
  ),
  numbering: SrgNumbering(episode: 'part', season: 'sez'),
  images: const _NoImages(),
  noEndYear: 2099,
  signedShowTitle: RegExp(r'\s\(signs\)$'),
  describedShowTitle: RegExp(r'\s\(described\)$'),
);

Map<String, dynamic> _show(String title) => {'id': title, 'title': title};

void main() {
  group('SRG ids', () {
    test('a native id survives a round trip', () {
      for (final native in [
        'show:5921007',
        'show:5615b0e0-868b',
        'season:5921007/s14',
        'season:x/y2026',
        'video:f40e',
      ]) {
        expect(SrgId.tryParse(native), isNotNull, reason: native);
      }
      expect(_unit.seasonRef('7', const SrgSeasonKey.year(2026)), const ReplayRef('xxplay', 'season:7/y2026'));
      expect(_unit.videoRef('abc'), const ReplayRef('xxplay', 'video:abc'));
    });

    test('ids that could change a request path are refused', () {
      expect(SrgId.tryParse('video:a/b'), isNull);
      expect(SrgId.tryParse('show:../x'), isNull);
      expect(SrgId.tryParse('season:x/z3'), isNull);
      expect(SrgId.tryParse('season:x'), isNull);
      expect(SrgId.tryParse('nonsense'), isNull);
    });
  });

  group('SRG numbering', () {
    test('words are the unit\'s own', () {
      expect(_unit.numbering.numbers({'title': 'Fatg (Sez 2, Part 5)'}), (season: 2, episode: 5));
      expect(_unit.numbering.numbers({'title': 'Fatg (Episode 5)'}), (season: null, episode: null));
      expect(_unit.numbering.cleanTitle('Fatg (Sez 2, Part 5)'), 'Fatg');
    });

    test('an S1E2 tag works in every language', () {
      expect(_unit.numbering.numbers({'title': 'Fatg S01E02'}), (season: 1, episode: 2));
    });
  });

  group('SRG show filter', () {
    test('sign copies go, described copies go next to their original', () {
      final shows = [_show('News'), _show('News (signs)'), _show('News (described)'), _show('Only (described)')];
      expect(srgVisibleShows(_unit, shows).map((s) => s['title']), ['News', 'Only (described)']);
    });
  });

  group('SRG geography memory', () {
    final ref = _unit.videoRef('v1');

    test('a title closed to the world is blocked abroad only', () {
      final memory = SrgGeoMemory()..note(ref, playableAbroad: false);
      expect(memory.verdict(ref, 'BE'), ReplayAvailability.geoBlocked);
      expect(memory.verdict(ref, 'CH'), isNull);
    });

    test('an open title and an unseen one are never blocked', () {
      final memory = SrgGeoMemory()..note(ref, playableAbroad: true);
      expect(memory.verdict(ref, 'BE'), isNull);
      expect(memory.verdict(_unit.videoRef('other'), 'BE'), isNull);
    });

    test('a later sighting replaces the earlier one', () {
      final memory = SrgGeoMemory()
        ..note(ref, playableAbroad: false)
        ..note(ref, playableAbroad: true);
      expect(memory.verdict(ref, 'DE'), isNull);
    });
  });

  group('SRG playback', () {
    test('the stream label follows the audio language', () {
      final resource = {
        ...srgResource('HLS', 'https://cdn.example/a.m3u8'),
        'audioTrackList': [
          {'locale': 'fr'},
        ],
      };
      final playback = srgParsePlayback(_unit, srgComposition('xx', resources: [resource]));
      expect(playback.streams.single.label, 'FR');
      final own = srgParsePlayback(
        _unit,
        srgComposition('xx', resources: [srgResource('HLS', 'https://cdn.example/a.m3u8')]),
      );
      expect(own.streams.single.label, 'RM');
    });

    test('a chapter that is missing is unknown, not playable', () {
      expect(srgParsePlayback(_unit, const {}).availability, ReplayAvailability.unknown);
    });

    test('a protected host is protected even without a scheme list', () {
      final composition = srgComposition('xx', resources: [srgResource('HLS', 'https://vod-drm.example/a.m3u8')]);
      expect(srgParsePlayback(_unit, composition).isPlayable, isFalse);
    });

    test('a window that has closed is expired', () {
      final composition = {
        'chapterList': [
          {'validTo': '2020-01-01T00:00:00+01:00'},
        ],
      };
      expect(srgParsePlayback(_unit, composition, now: DateTime.utc(2026)).availability, ReplayAvailability.expired);
    });
  });

  group('SRG image buckets', () {
    test('the next width up is used, and the largest caps it', () {
      expect(srgWidthBucket(const [240, 480, 960], 300), 480);
      expect(srgWidthBucket(const [240, 480, 960], 5000), 960);
      expect(isSrgFallbackImage('https://il.srgssr.ch/image-service/dynamic/a.jpg'), isTrue);
    });
  });
}
