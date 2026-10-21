import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'rtsplay_availability.dart';
import 'rtsplay_ids.dart';
import 'rtsplay_numbering.dart';

/// Where an item was found, so an episode knows its show and season without a second call.
class RtsContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const RtsContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = RtsContext();
}

/// Maps a video from any list, search or media composition to a [ReplayTitle].
///
/// Returns null for audio, live streams and anything else that is not a recorded video.
ReplayTitle? rtsTitleFromMedia(Map<String, dynamic> item, {RtsContext context = RtsContext.none, DateTime? now}) {
  final id = item['id']?.toString();
  if (id == null || item['mediaType'] != 'VIDEO' || !(item['urn'] as String? ?? '').startsWith('urn:rts:video:')) {
    return null;
  }
  final type = item['type'] as String?;
  final isClip = type == 'CLIP' || type == 'EXTRACT' || type == 'TRAILER';
  if (type != 'EPISODE' && !isClip) return null;

  final show = item['show'] as Map<String, dynamic>?;
  final showId = show?['id']?.toString();
  final numbers = rtsNumbers(item);
  final isFilm = !isClip && (showId == null || (rtsFilmUmbrellaShows.contains(showId) && numbers.episode == null));
  final kind = isClip
      ? ReplayKind.clip
      : isFilm
      ? ReplayKind.movie
      : ReplayKind.episode;

  final showRef = context.show ?? (isFilm || showId == null ? null : rtsShowRef(showId));
  final key = kind == ReplayKind.episode && showId != null ? _seasonKey(show, item, numbers) : null;
  final moment = now ?? DateTime.now();

  return ReplayTitle(
    ref: rtsVideoRef(id),
    kind: kind,
    title: rtsCleanTitle(item['title'] as String? ?? id),
    summary: _text(item['description']),
    backdropUrl: _text(item['imageUrl']),
    durationSeconds: _seconds(item['duration']),
    year: _airYear(item['date']),
    genres: _genres(show),
    airDate: _date(item['date']),
    availableUntil: _endOfRights(item['validTo']),
    availability: rtsAvailability(item, moment),
    seasonNumber: key == null ? null : numbers.season ?? context.seasonNumber ?? key.number ?? key.year,
    episodeNumber: key == null ? null : numbers.episode,
    showRef: showRef,
    showTitle: context.showTitle ?? (isFilm ? null : show?['title'] as String?),
    seasonRef: key == null ? null : context.season ?? rtsSeasonRef(showId!, key),
  );
}

/// Maps a show object from a show list, a section or a search result.
ReplayTitle? rtsTitleFromShow(Map<String, dynamic> show) {
  final id = show['id']?.toString();
  final title = (show['title'] as String?)?.trim();
  if (id == null || title == null || title.isEmpty) return null;
  final posterIsGeneric = show['posterImageIsFallbackUrl'] == true;
  return ReplayTitle(
    ref: rtsShowRef(id),
    kind: ReplayKind.show,
    title: title,
    summary: _text(show['description']),
    posterUrl: posterIsGeneric ? null : _text(show['posterImageUrl']),
    backdropUrl: _text(show['bannerImageUrl']) ?? _text(show['imageUrl']),
    genres: _genres(show),
  );
}

/// The "Signé" copies of a show carry sign-language interpretation and duplicate the original in every list.
bool rtsIsSignedShow(String title) => RegExp(r'\s-\s*Sign[ée]$', caseSensitive: false).hasMatch(title.trim());

int? rtsEpisodeCount(Map<String, dynamic>? show) => (show?['numberOfEpisodes'] as num?)?.toInt();

/// The season an episode belongs to when nothing but the item itself is known.
///
/// An episode numbered without a season is taken for season 1. An unnumbered episode of a long show
/// belongs to the year it aired; of a short show, to the unnumbered group.
RtsSeasonKey _seasonKey(Map<String, dynamic>? show, Map<String, dynamic> item, RtsNumbers numbers) {
  if (numbers.season != null) return RtsSeasonKey.numbered(numbers.season!);
  if (numbers.episode != null) return const RtsSeasonKey.numbered(1);
  final year = _airYear(item['date']);
  final isLong = (rtsEpisodeCount(show) ?? 0) > rtsLongShowThreshold;
  return isLong && year != null ? RtsSeasonKey.year(year) : const RtsSeasonKey.other();
}

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

/// RTS writes "no end" as a date in 2100.
DateTime? _endOfRights(Object? iso) {
  final end = _date(iso);
  return end == null || end.year >= 2100 ? null : end;
}

/// Maps the video a media composition describes. The composition keeps the show and episode blocks
/// beside the chapter, not inside it.
ReplayTitle? rtsTitleFromComposition(Map<String, dynamic> composition, {DateTime? now}) {
  final chapters = composition['chapterList'];
  final chapter = chapters is List && chapters.isNotEmpty ? chapters.first : null;
  if (chapter is! Map<String, dynamic>) return null;
  return rtsTitleFromMedia({'show': composition['show'], 'episode': composition['episode'], ...chapter}, now: now);
}
