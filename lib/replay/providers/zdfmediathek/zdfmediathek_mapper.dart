import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'zdfmediathek_dates.dart';
import 'zdfmediathek_geo.dart';
import 'zdfmediathek_images.dart';
import 'zdfmediathek_numbering.dart';
import 'zdfmediathek_text.dart';

const zdfmediathekSourceId = 'zdfmediathek';

ReplayRef zdfRef(String nativeId) => ReplayRef(zdfmediathekSourceId, nativeId);

/// Where a video was found, so an episode knows its show and season. [episodeNumber] replaces the one the video
/// carries when the catalogue derives the numbering itself.
class ZdfContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;
  final int? episodeNumber;

  const ZdfContext({this.show, this.showTitle, this.season, this.seasonNumber, this.episodeNumber});

  static const none = ZdfContext();
}

const _genreBySection = {
  'serien': 'Serien',
  'dokumentation': 'Dokumentation',
  'kinder': 'Kinder',
  'show': 'Show',
  'kultur': 'Kultur',
  'comedy': 'Comedy',
  'politik': 'Politik',
  'nachrichten': 'Nachrichten',
  'sport': 'Sport',
  'filme': 'Filme',
};

/// Turns ZDF teasers and documents into neutral titles, and notes each video's geo flag on the way.
class ZdfMapper {
  final ZdfGeoLedger geo;
  final DateTime Function() now;

  ZdfMapper(this.geo, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  /// One teaser or document, or null for what cannot be opened here: live channels, categories, links out and
  /// teasers without an id.
  ReplayTitle? title(Map<String, dynamic> item, {ZdfContext context = ZdfContext.none, String? clusterName}) {
    final id = item['id'];
    if (id is! String || id.isEmpty || item['hasVideo'] == false) return null;
    return switch (item['type']) {
      'brand' || 'topic' => _show(item, id),
      'video' => _video(item, id, context, clusterName),
      _ => null,
    };
  }

  /// The show described by a brand or topic document. The page keeps its short text and logo beside the document.
  ReplayTitle? showFromPage(Map<String, dynamic> page) {
    final document = page['document'];
    if (document is! Map<String, dynamic>) return null;
    final header = page['stageHeader'];
    return title({
      ...document,
      'shortText': page['shortText'],
      if (header is Map && header['logo'] != null) 'logo': header['logo'],
    });
  }

  ReplayTitle _show(Map<String, dynamic> item, String id) {
    final shortText = item['shortText'];
    return ReplayTitle(
      ref: zdfRef(id),
      kind: ReplayKind.show,
      title: zdfText(item['titel']) ?? id,
      summary:
          zdfText(shortText is Map ? shortText['text'] : null) ??
          zdfText(item['beschreibung']) ??
          zdfText(item['textLong']),
      posterUrl: zdfPickImage([item['image'], item['teaserBild']], ZdfPicture.poster),
      backdropUrl: zdfPickImage([item['teaserBild'], item['image']], ZdfPicture.backdrop),
      logoUrl: zdfPickImage([item['logo']], ZdfPicture.logo),
      genres: _genres(item),
    );
  }

  ReplayTitle? _video(Map<String, dynamic> item, String id, ZdfContext context, String? clusterName) {
    final contentType = item['contentType'];
    final videoType = item['currentVideoType'];
    if (contentType == 'live' || videoType == 'live') return null;

    final ref = zdfRef(id);
    geo.record(ref, item['geoLocation']);
    final numbers = zdfNumbers(item, clusterName: clusterName);
    final brandId = zdfText(item['brandId']);
    final isEpisode = contentType == 'episode' && videoType == 'episode';
    final inShow = brandId != null || numbers.season != null || numbers.episode != null;
    final kind = !isEpisode ? ReplayKind.clip : (inShow ? ReplayKind.episode : ReplayKind.movie);
    final showRef = context.show ?? (brandId == null ? null : zdfRef(brandId));
    final seasonNumber = context.seasonNumber ?? numbers.season;
    final showName = kind == ReplayKind.movie
        ? null
        : zdfText(item['brandTitle']) ?? _showFromHeadline(item['headline']);

    return ReplayTitle(
      ref: ref,
      kind: kind,
      title: zdfText(item['titel']) ?? id,
      subtitle: showName,
      summary: zdfText(item['beschreibung']),
      posterUrl: zdfPickImage([item['teaserBild']], ZdfPicture.poster),
      backdropUrl: zdfPickImage([item['teaserBild']], ZdfPicture.backdrop),
      durationSeconds: (item['length'] as num?)?.toInt(),
      year: _productionYear(item),
      genres: _genres(item),
      contentRating: _rating(item['fsk']),
      airDate: _airDate(item),
      availableUntil: _availableUntil(item),
      availability: _availability(item),
      seasonNumber: seasonNumber,
      episodeNumber: context.episodeNumber ?? numbers.episode,
      showRef: showRef,
      showTitle: context.showTitle ?? (showRef == null ? null : showName),
      seasonRef: context.season ?? _seasonRef(brandId, numbers.season),
    );
  }

  ReplayRef? _seasonRef(String? brandId, int? season) =>
      brandId == null || season == null ? null : zdfRef('$brandId/$season');

  ReplayAvailability _availability(Map<String, dynamic> item) {
    final end = _availableUntil(item);
    if (end != null && end.isBefore(now())) return ReplayAvailability.expired;
    final start = zdfLocalDate(item['visibleFrom']);
    if (start != null && start.isAfter(now())) return ReplayAvailability.upcoming;
    return ReplayAvailability.playable;
  }

  DateTime? _availableUntil(Map<String, dynamic> item) =>
      zdfIsoDate(item['offlineAvailability']) ?? zdfLocalDate(item['timetolive']);

  /// Original broadcast first, then the day it went online, then the editorial date, then a date in the title.
  DateTime? _airDate(Map<String, dynamic> item) {
    final editorial = ((item['contentAttributes'] as Map?)?['editorialDate'] as Map?)?['title'];
    return zdfLocalDate(item['airtime']) ??
        zdfLocalDate(item['date']) ??
        zdfLocalDate(item['visibleFrom']) ??
        zdfLocalDate(editorial) ??
        zdfTitleDate(item['titel'] as String?);
  }
}

/// `Doku | ZDFzeit` on a document, `Terra Xplore` on a teaser: the part after the last bar is the show.
String? _showFromHeadline(Object? headline) {
  final text = zdfText(headline);
  if (text == null) return null;
  return zdfText(text.substring(text.lastIndexOf('|') + 1));
}

List<String> _genres(Map<String, dynamic> item) {
  final path = item['structureNodePath'];
  if (path is! String) return const [];
  final sections = path.split('/');
  final genre = sections.length > 2 ? _genreBySection[sections[2]] : null;
  return genre == null ? const [] : [genre];
}

int? _productionYear(Map<String, dynamic> item) {
  final year = ((item['contentAttributes'] as Map?)?['productionYear'] as Map?)?['title'];
  return year is String ? int.tryParse(year) : null;
}

String? _rating(Object? fsk) => switch (fsk) {
  'fsk6' => '6+',
  'fsk12' => '12+',
  'fsk16' => '16+',
  'fsk18' => '18+',
  _ => null,
};
