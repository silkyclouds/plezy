import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/err/err_images.dart';
import 'package:plezy/replay/providers/err/err_mapper.dart';
import 'package:plezy/replay/providers/err/err_numbering.dart';
import 'package:plezy/replay/providers/err/err_page_mapper.dart';
import 'package:plezy/replay/providers/err/err_playback.dart';
import 'package:plezy/replay/providers/err/err_rails.dart';
import 'package:plezy/replay/providers/err/err_season_list.dart';

import 'err_fake_site.dart';

Map<String, dynamic> _crop(int w, int h, String url) => {'type': w, 'w': w, 'h': h, 'url': url};

Map<String, dynamic> _photos(List<Map<String, dynamic>> crops) => {
  'photoTypes': {for (var i = 0; i < crops.length; i++) '$i': crops[i]},
};

Map<String, dynamic> _item(String type, {List<Object?>? medias, Map<String, dynamic> extra = const {}}) => {
  'id': 5,
  'type': type,
  'heading': 'Pealkiri',
  'medias': ?medias,
  ...extra,
};

void errUnitCases() {
  group('ERR artwork', () {
    final landscape = [
      _crop(120, 80, 'https://s.err.ee/a/1.jpg'),
      _crop(324, 182, 'https://s.err.ee/a/34.jpg'),
      _crop(600, 338, 'https://s.err.ee/a/17.jpg'),
      _crop(1920, 1080, 'https://s.err.ee/a/2.jpg'),
      _crop(200, 200, 'https://s.err.ee/a/44.jpg'),
      _crop(180, 270, 'https://s.err.ee/a/60.jpg'),
    ];

    test('a backdrop keeps wide crops only', () {
      final reference = errBackdropReference({
        'horizontalPhotos': [_photos(landscape)],
      });
      expect(reference, startsWith(errImagePrefix));
      expect(
        reference,
        allOf(contains('324x182'), contains('1920x1080'), isNot(contains('120x80')), isNot(contains('200x200'))),
      );
      expect(reference, isNot(contains('180x270')));
    });

    test('a poster keeps portrait crops only', () {
      final reference = errPosterReference({
        'verticalPhotos': [_photos(landscape)],
      });
      expect(reference, '${errImagePrefix}180x270=https://s.err.ee/a/60.jpg');
    });

    test('a set without a fitting crop falls through to the next set', () {
      final reference = errBackdropReference({
        'horizontalPhotos': [
          _photos([_crop(120, 80, 'https://s.err.ee/a/1.jpg')]),
        ],
        'photos': [_photos(landscape)],
      });
      expect(reference, contains('1920x1080'));
      expect(errBackdropReference({'horizontalPhotos': []}), isNull);
      expect(errPosterReference({'verticalPhotos': []}), isNull);
    });

    test('at most five sizes are kept, from the smallest to the largest', () {
      final many = [for (var w = 300; w <= 1200; w += 100) _crop(w, w * 9 ~/ 16, 'https://s.err.ee/a/$w.jpg')];
      final reference = errBackdropReference({
        'photos': [_photos(many)],
      })!;
      expect(reference.split(' '), hasLength(5));
      expect(reference, allOf(contains('300x'), contains('1200x')));
    });

    test('the smallest crop that covers the width is chosen', () {
      final reference = errBackdropReference({
        'photos': [_photos(landscape)],
      })!;
      expect(errImageUrl(reference, width: 300), 'https://s.err.ee/a/34.jpg');
      expect(errImageUrl(reference, width: 500), 'https://s.err.ee/a/17.jpg');
      expect(errImageUrl(reference, width: 9000), 'https://s.err.ee/a/2.jpg');
      expect(errImageUrl(reference), 'https://s.err.ee/a/17.jpg');
    });

    test('only references of this provider are claimed', () {
      expect(isErrImage('${errImagePrefix}300x200=https://s.err.ee/a.jpg'), isTrue);
      expect(isErrImage('https://s.err.ee/a.jpg'), isFalse);
      expect(errImageUrl('https://elsewhere/a.jpg'), 'https://elsewhere/a.jpg');
    });

    test('a card without a portrait uses its landscape picture as poster', () {
      final title = errTitleFromItem(
        _item(
          'movie',
          extra: {
            'horizontalPhotos': [_photos(landscape)],
          },
        ),
      );
      expect(title!.posterUrl, title.backdropUrl);
      expect(title.backdropUrl, isNotNull);
    });
  });

  group('ERR numbering', () {
    test('episode numbers are read from Estonian, English and Russian titles', () {
      expect(errEpisodeFromTitle('Kodu', '5. osa'), 5);
      expect(errEpisodeFromTitle('Kodu', 'Osa 12: Kaja'), 12);
      expect(errEpisodeFromTitle('Home', 'Episode 7'), 7);
      expect(errEpisodeFromTitle('Дом', 'Серия 3'), 3);
      expect(errEpisodeFromTitle('Kodu 3. osa', ''), 3);
    });

    test('a title with no number gives none', () {
      expect(errEpisodeFromTitle('Allo Allo!', 'Britid tulevad'), isNull);
      expect(errEpisodeFromTitle(null, null), isNull);
      expect(errEpisodeFromTitle('Osa 0', null), isNull);
    });

    test('season numbers are read from titles', () {
      expect(errSeasonFromTitle('Kodu', '2. hooaeg'), 2);
      expect(errSeasonFromTitle('Kodu', 'Hooaeg 4'), 4);
      expect(errSeasonFromTitle('Kodu', 'Britid tulevad'), isNull);
    });

    test('ERR numbers win over numbers in the title', () {
      final title = errTitleFromItem(_item('episode', extra: {'subHeading': '9. osa', 'episode': 4, 'season': 2}));
      expect(title!.episodeNumber, 4);
      expect(title.seasonNumber, 2);
    });
  });

  group('ERR item kinds', () {
    test('a series is a show whatever else it carries', () {
      expect(errTitleFromItem(_item('series', medias: []))!.kind, ReplayKind.show);
    });

    test('a catalogue show with media is a film and without media a programme', () {
      expect(errTitleFromItem(_item('show', medias: [{}]))!.kind, ReplayKind.movie);
      expect(errTitleFromItem(_item('show', medias: []))!.kind, ReplayKind.show);
      expect(errTitleFromItem(_item('movie', medias: []))!.kind, ReplayKind.show);
      expect(errTitleFromItem(_item('movie', medias: [{}]))!.kind, ReplayKind.movie);
    });

    test('a card of type movie or show without a media list keeps its type', () {
      expect(errTitleFromItem(_item('movie'))!.kind, ReplayKind.movie);
      expect(errTitleFromItem(_item('show'))!.kind, ReplayKind.show);
    });

    test('cards with nothing to play, or of unknown types, are dropped', () {
      expect(errTitleFromItem(_item('movie', extra: {'hasActiveMedia': false})), isNull);
      expect(errTitleFromItem(_item('radio')), isNull);
      expect(errTitleFromItem({'type': 'movie'}), isNull);
    });

    test('an episode takes its subheading as title and the heading as show', () {
      final title = errTitleFromItem(_item('episode', extra: {'subHeading': 'Britid tulevad', 'rootContentId': 77}));
      expect(title!.title, 'Britid tulevad');
      expect(title.showTitle, 'Pealkiri');
      expect(title.showRef!.nativeId, '77');
    });

    test('headings lose markup and non-breaking spaces', () {
      final title = errTitleFromItem(_item('movie', extra: {'heading': 'Kuld&nbsp;&amp;&nbsp;hõbe'}));
      expect(title!.title, 'Kuld & hõbe');
    });

    test('dates are Unix seconds and zero means none', () {
      expect(errDate(1608210000), DateTime.utc(2020, 12, 17, 13));
      expect(errDate(0), isNull);
      expect(errDate(null), isNull);
    });
  });

  group('ERR rows', () {
    Map<String, dynamic> row(String header, String url, {Map<String, dynamic> extra = const {}}) => {
      'header': header,
      'headerUrl': url,
      'data': [_item('movie')],
      ...extra,
    };

    test('only a slug links to a listing', () {
      final rails = errRailsFromCategory({
        'frontPage': [
          row('A', '/eesti'),
          row('B', '/1609714886'),
          row('C', '/sarjad/draama'),
          row('D', 'https://jupiter.err.ee/1'),
          row('E', ''),
        ],
      });
      expect(rails.map((r) => r.moreBrowseId), ['eesti', null, null, null, null]);
    });

    test('live blocks, signed-in rows, banners and empty rows are dropped', () {
      final rails = errRailsFromCategory({
        'frontPage': [
          row('Otse', '', extra: {'liveBlock': true}),
          row('Jätka', '', extra: {'userBasedTimeline': true}),
          row(
            'Reklaam',
            '',
            extra: {
              'manual': {'banner': true},
            },
          ),
          row('Tühi', '', extra: {'data': []}),
          row('', ''),
          row('Hea', ''),
        ],
      });
      expect(rails.map((r) => r.title), ['Hea']);
    });
  });

  group('ERR season lists', () {
    test('the three shapes parse into entries', () {
      final seasonal = errParseSeasonList({
        'contentOrder': 'asc',
        'items': [
          {'id': 2, 'name': '2', 'firstContentId': 20},
          {'id': 1, 'name': '1', 'firstContentId': 10, 'contents': []},
        ],
      })!;
      expect(seasonal.entries.map((e) => e.key), [2, 1]);
      expect(seasonal.entry(1)!.contents, isEmpty);
      expect(seasonal.entry(2)!.contents, isNull);
      expect(seasonal.descending, isFalse);

      final short = errParseSeasonList({
        'contentOrder': 'desc',
        'items': [
          {'firstContentId': 30, 'contents': []},
        ],
      })!;
      expect(short.entries.single.key, 1);
      expect(short.descending, isTrue);

      final monthly = errParseSeasonList({
        'items': [
          {
            'id': 2025,
            'name': '2025',
            'firstContentId': 40,
            'items': [
              {'id': 12, 'name': 'detsember', 'firstContentId': 40},
            ],
          },
        ],
      })!;
      expect(monthly.entries.single.isYear, isTrue);
      expect(monthly.entries.single.months.single.key, 12);
    });

    test('a page without a usable list gives none', () {
      expect(errParseSeasonList(null), isNull);
      expect(errParseSeasonList(<Object>[]), isNull);
      expect(errParseSeasonList({'items': []}), isNull);
      expect(
        errParseSeasonList({
          'items': [
            {'id': 1},
          ],
        }),
        isNull,
      );
    });

    test('the active season is the one flagged, in a year or a month', () {
      expect(
        ErrSeasonList.activeKey({
          'items': [
            {'id': 1},
            {'id': 3, 'active': true},
          ],
        }),
        3,
      );
      expect(
        ErrSeasonList.activeKey({
          'items': [
            {
              'id': 2025,
              'items': [
                {'id': 12, 'active': true},
              ],
            },
          ],
        }),
        2025,
      );
      expect(
        ErrSeasonList.activeKey({
          'items': [
            {'id': 1},
          ],
        }),
        isNull,
      );
    });
  });

  group('ERR stream addresses and rights windows', () {
    test('protocol-relative addresses get a scheme, the first key wins', () {
      expect(
        errMasterUrl({'hls': '//vod.err.ee/hls/vod/a/3/v/master.m3u8'}).toString(),
        'https://vod.err.ee/hls/vod/a/3/v/master.m3u8',
      );
      expect(errMasterUrl({'hls': '', 'hlsNew': 'https://vod.err.ee/b.m3u8'}).toString(), 'https://vod.err.ee/b.m3u8');
      expect(errMasterUrl({'dash': '//vod.err.ee/c.mpd'}), isNull);
    });

    test('the end of the covering window is shown, an open end is not', () {
      final now = DateTime.utc(2026, 10, 22);
      int seconds(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
      Map<String, dynamic> media(DateTime start, DateTime end) => {
        'periods': [
          {'publicStart': seconds(start), 'publicEnd': seconds(end)},
        ],
      };
      expect(errAvailableUntil(media(DateTime.utc(2026, 9), DateTime.utc(2027, 1)), now), DateTime.utc(2027, 1));
      expect(errAvailableUntil(media(DateTime.utc(2026, 9), DateTime.utc(2105, 1)), now), isNull);
      expect(errAvailableUntil(media(DateTime.utc(2020), DateTime.utc(2021)), now), isNull);
      expect(errAvailableUntil(media(DateTime.utc(2027), DateTime.utc(2028)), now), isNull);
      expect(errAvailableUntil(const {}, now), isNull);
    });

    test('a recorded film page shows no end date for an archive item', () {
      final film = errTitleFromPage(errFixture('movie_page_ok'), now: DateTime.utc(2026, 10, 22));
      expect(film!.availableUntil, isNull);
      expect(film.airDate, DateTime.utc(2020, 12, 17, 13));
    });
  });
}
