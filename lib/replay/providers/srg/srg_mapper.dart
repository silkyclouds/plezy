import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'srg_availability.dart';
import 'srg_geo.dart';
import 'srg_ids.dart';
import 'srg_numbering.dart';
import 'srg_unit.dart';

/// A show with more episodes than this is listed by broadcast year when its episodes carry no season number.
const srgLongShowThreshold = 100;

/// Where an item was found, so an episode knows its show and season without a second call.
class SrgContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const SrgContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = SrgContext();
}

/// Maps Integration Layer objects to [ReplayTitle]s for one business unit.
class SrgMapper {
  final SrgUnit unit;

  /// Told about every title's `playableAbroad` flag as titles go by, when the caller wants forecasts.
  final SrgGeoMemory? geo;

  SrgMapper(this.unit, {this.geo});

  /// Maps a video from any list, search or media composition.
  ///
  /// Returns null for audio, live streams and anything else that is not a recorded video.
  ReplayTitle? fromMedia(Map<String, dynamic> item, {SrgContext context = SrgContext.none, DateTime? now}) {
    final id = item['id']?.toString();
    if (id == null || item['mediaType'] != 'VIDEO' || !(item['urn'] as String? ?? '').startsWith(unit.videoUrnPrefix)) {
      return null;
    }
    final type = item['type'] as String?;
    final isClip = type == 'CLIP' || type == 'EXTRACT' || type == 'TRAILER';
    if (type != 'EPISODE' && !isClip) return null;

    final show = item['show'] as Map<String, dynamic>?;
    final showId = show?['id']?.toString();
    final numbers = unit.numbering.numbers(item);
    final isFilm = !isClip && (showId == null || (unit.filmUmbrellaShows.contains(showId) && numbers.episode == null));
    final kind = isClip
        ? ReplayKind.clip
        : isFilm
        ? ReplayKind.movie
        : ReplayKind.episode;

    final showRef = context.show ?? (isFilm || showId == null ? null : unit.showRef(showId));
    final key = kind == ReplayKind.episode && showId != null ? _seasonKey(show, item, numbers) : null;
    final moment = now ?? DateTime.now();
    final ref = unit.videoRef(id);
    final abroad = item['playableAbroad'];
    if (abroad is bool) geo?.note(ref, playableAbroad: abroad);

    return ReplayTitle(
      ref: ref,
      kind: kind,
      title: unit.numbering.cleanTitle(item['title'] as String? ?? id),
      summary: _text(item['description']),
      backdropUrl: _text(item['imageUrl']),
      durationSeconds: _seconds(item['duration']),
      year: _airYear(item['date']),
      genres: _genres(show),
      airDate: _date(item['date']),
      availableUntil: _endOfRights(item['validTo']),
      availability: srgAvailability(item, moment),
      seasonNumber: key == null ? null : numbers.season ?? context.seasonNumber ?? key.number ?? key.year,
      episodeNumber: key == null ? null : numbers.episode,
      showRef: showRef,
      showTitle: context.showTitle ?? (isFilm ? null : show?['title'] as String?),
      seasonRef: key == null ? null : context.season ?? unit.seasonRef(showId!, key),
    );
  }

  /// Maps a show object from a show list, a section or a search result.
  ReplayTitle? fromShow(Map<String, dynamic> raw) {
    final id = raw['id']?.toString();
    final title = (raw['title'] as String?)?.trim();
    if (id == null || title == null || title.isEmpty) return null;
    final posterIsGeneric = raw['posterImageIsFallbackUrl'] == true;
    return ReplayTitle(
      ref: unit.showRef(id),
      kind: ReplayKind.show,
      title: title,
      summary: _text(raw['description']),
      posterUrl: posterIsGeneric ? null : _text(raw['posterImageUrl']),
      backdropUrl: _text(raw['bannerImageUrl']) ?? _text(raw['imageUrl']),
      genres: _genres(raw),
    );
  }

  /// Maps the video a media composition describes. The composition keeps the show and episode blocks
  /// beside the chapter, not inside it.
  ReplayTitle? fromComposition(Map<String, dynamic> raw, {DateTime? now}) {
    final chapters = raw['chapterList'];
    final chapter = chapters is List && chapters.isNotEmpty ? chapters.first : null;
    if (chapter is! Map<String, dynamic>) return null;
    return fromMedia({'show': raw['show'], 'episode': raw['episode'], ...chapter}, now: now);
  }

  /// The broadcaster writes "no end" as a date far in the future.
  DateTime? _endOfRights(Object? iso) {
    final end = _date(iso);
    return end == null || end.year >= unit.noEndYear ? null : end;
  }
}

/// The season an episode belongs to when nothing but the item itself is known.
///
/// An episode numbered without a season is taken for season 1. An unnumbered episode of a long show
/// belongs to the year it aired; of a short show, to the unnumbered group.
SrgSeasonKey _seasonKey(Map<String, dynamic>? show, Map<String, dynamic> item, SrgNumbers numbers) {
  if (numbers.season != null) return SrgSeasonKey.numbered(numbers.season!);
  if (numbers.episode != null) return const SrgSeasonKey.numbered(1);
  final year = _airYear(item['date']);
  final isLong = (srgEpisodeCount(show) ?? 0) > srgLongShowThreshold;
  return isLong && year != null ? SrgSeasonKey.year(year) : const SrgSeasonKey.other();
}

int? srgEpisodeCount(Map<String, dynamic>? show) => (show?['numberOfEpisodes'] as num?)?.toInt();

int? _seconds(Object? milliseconds) => milliseconds is num && milliseconds >= 1000 ? milliseconds ~/ 1000 : null;

String? _text(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

List<String> _genres(Map<String, dynamic>? show) {
  final topics = show?['topicList'];
  if (topics is! List) return const [];
  return [
    for (final topic in topics)
      if (topic is Map && topic['title'] is String) topic['title'] as String,
  ];
}

DateTime? _date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

/// Broadcast year as written in the local date, so a New Year's Eve evening is not moved to the next year.
int? _airYear(Object? iso) => iso is String && iso.length >= 4 ? int.tryParse(iso.substring(0, 4)) : null;
