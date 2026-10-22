import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'tvpvod_images.dart';
import 'tvpvod_numbering.dart';
import 'tvpvod_refs.dart';

/// Where a title was found, for the cases where the item itself does not say.
class TvpContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const TvpContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = TvpContext();
}

/// Maps one product record (a list entry, a row card or a detail page) to a [ReplayTitle].
///
/// Live channels, promo banners and nested collections return null: only series, films and episodes are titles.
ReplayTitle? tvpTitleFromItem(Map<String, dynamic> item, {TvpContext context = TvpContext.none, DateTime? now}) {
  final kind = switch (item['type']) {
    'SERIAL' => ReplayKind.show,
    'VOD' => ReplayKind.movie,
    'EPISODE' => ReplayKind.episode,
    _ => null,
  };
  final id = (item['id'] as num?)?.toInt();
  if (kind == null || id == null) return null;

  final rawTitle = _clean(item['title'] as String?) ?? '$id';
  final TvpEpisodeLabel label = kind == ReplayKind.episode
      ? tvpEpisodeLabel(rawTitle, item['number'])
      : (number: null, title: rawTitle);
  final parents = kind == ReplayKind.episode ? _parents(item, context) : TvpContext.none;
  final backdrop = tvpImageReference(item['artworks'], '16x9') ?? tvpImageReference(item['images'], '16x9');

  return ReplayTitle(
    ref: tvpRef(id),
    kind: kind,
    title: label.title,
    summary: _summary(item),
    posterUrl: tvpImageReference(item['images'], '3x4') ?? tvpImageReference(item['images'], '16x9') ?? backdrop,
    backdropUrl: backdrop,
    logoUrl: tvpImageReference(item['titleImages'], '16x9'),
    durationSeconds: _positive(item['duration']),
    year: _positive(item['year']),
    genres: _names(item['genres']),
    directors: _names(item['directors']),
    cast: _names(item['actors']),
    contentRating: _rating(item['rating']),
    airDate: kind == ReplayKind.episode ? _date(item['since']) : null,
    availableUntil: _expiry(item['till']),
    availability: _availability(item, kind, now ?? DateTime.now()),
    seasonNumber: parents.seasonNumber,
    episodeNumber: label.number,
    showRef: parents.show,
    showTitle: parents.showTitle,
    seasonRef: parents.season,
  );
}

/// Titles of a list of product records, without unplayable entries and without repeats.
List<ReplayTitle> tvpTitlesFromItems(Iterable<Object?> items) {
  final seen = <ReplayRef>{};
  return [
    for (final raw in items)
      if (raw is Map<String, dynamic>)
        if (tvpTitleFromItem(raw) case final title? when seen.add(title.ref)) title,
  ];
}

/// The show and season an episode record names, unless the caller already knows them.
TvpContext _parents(Map<String, dynamic> item, TvpContext given) {
  final season = item['season'];
  final serial = season is Map ? season['serial'] : null;
  final serialId = serial is Map ? serial['id'] : null;
  final seasonId = season is Map ? season['id'] : null;
  final number = season is Map ? _positive(season['number']) : null;
  return TvpContext(
    show: given.show ?? (serialId == null ? null : tvpRef(serialId)),
    showTitle: given.showTitle ?? (serial is Map ? _clean(serial['title'] as String?) : null),
    season: given.season ?? (serialId == null || seasonId == null ? null : tvpSeasonRef(serialId, seasonId)),
    seasonNumber: given.seasonNumber ?? number,
  );
}

ReplayAvailability _availability(Map<String, dynamic> item, ReplayKind kind, DateTime now) {
  final until = _date(item['till']);
  if (until != null && until.isBefore(now)) return ReplayAvailability.expired;
  final from = _date(item['since']);
  if (from != null && from.isAfter(now)) return ReplayAvailability.upcoming;
  final playable = kind != ReplayKind.show;
  if (playable && (item['payable'] == true || item['loginRequired'] == true)) return ReplayAvailability.loginRequired;
  return ReplayAvailability.playable;
}

String? _summary(Map<String, dynamic> item) {
  for (final key in ['description', 'lead']) {
    final text = htmlToText(item[key] as String?);
    if (text.isNotEmpty) return text;
  }
  return null;
}

List<String> _names(Object? list) {
  if (list is! List) return const [];
  return [for (final entry in list.whereType<Map>()) ?_clean(entry['name'] as String?)];
}

String? _rating(Object? age) => age is num && age > 0 ? '${age.toInt()}+' : null;

int? _positive(Object? value) => value is num && value > 0 ? value.toInt() : null;

String? _clean(String? text) {
  final collapsed = text?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return collapsed == null || collapsed.isEmpty ? null : collapsed;
}

DateTime? _date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

/// Series are licensed "until 2120", which only means no end is planned.
DateTime? _expiry(Object? iso) {
  final until = _date(iso);
  return until == null || until.year >= 2100 ? null : until;
}
