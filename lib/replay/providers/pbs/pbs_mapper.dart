import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'pbs_ids.dart';

/// Where a video was found, so it knows its show and season even when its own record does not say.
class PbsContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  /// The video is listed inside a season, so it is an episode even without an episode number.
  final bool inSeason;

  const PbsContext({this.show, this.showTitle, this.season, this.seasonNumber, this.inSeason = false});

  static const none = PbsContext();
}

/// Maps a show record, from a search, a genre page or the show's own page. Null for records without a slug or title.
ReplayTitle? pbsShowTitle(Map<String, dynamic> show) {
  final slug = show['slug'];
  final title = _text(show['title']);
  if (slug is! String || title == null) return null;
  final images = show['images'] as Map<String, dynamic>? ?? const {};
  final genre = _text((show['genre'] as Map?)?['title']);
  return ReplayTitle(
    ref: pbsShowRef(slug),
    kind: ReplayKind.show,
    title: title,
    summary: _summary(show['description_long'], show['description_short']),
    posterUrl: _image(images, ['show-poster2x3']) ?? _text(show['poster']),
    backdropUrl: _image(images, ['show-mezzanine16x9', 'show-banner']),
    logoUrl: _image(images, ['show-logo', 'color-logo-41']),
    genres: genre == null ? const [] : [genre],
  );
}

/// Maps a season of [show], whose slug is [showSlug]. A season that only has clips and previews says so in its name.
ReplayTitle pbsSeasonTitle(Map<String, dynamic> season, ReplayTitle show, String showSlug) {
  final ordinal = (season['ordinal'] as num).toInt();
  final flags = season['flags'] as Map? ?? const {};
  final images = season['images'] as Map<String, dynamic>? ?? const {};
  return ReplayTitle(
    ref: pbsSeasonRef(showSlug, season['cid'] as String),
    kind: ReplayKind.season,
    title: _seasonName(ordinal, _text(season['title']), extrasOnly: flags['has_episodes'] != true),
    posterUrl: show.posterUrl,
    backdropUrl: _image(images, ['asset-mezzanine-16x9']) ?? show.backdropUrl,
    seasonNumber: ordinal,
    showRef: show.ref,
    showTitle: show.title,
  );
}

/// The synthetic season that holds a show's stand-alone specials. Season zero is the usual number for specials.
ReplayTitle pbsSpecialsTitle(ReplayTitle show, String showSlug, int count) => ReplayTitle(
  ref: pbsSeasonRef(showSlug, pbsSpecialsSeason),
  kind: ReplayKind.season,
  title: 'Specials',
  posterUrl: show.posterUrl,
  backdropUrl: show.backdropUrl,
  seasonNumber: 0,
  childCount: count,
  showRef: show.ref,
  showTitle: show.title,
);

/// Maps a video record from a search, a season list, a show page or a video page. Null for records that are not
/// videos, such as web links in search results.
ReplayTitle? pbsVideoTitle(Map<String, dynamic> video, {PbsContext context = PbsContext.none, DateTime? now}) {
  final mediaId = video['legacy_tp_media_id'];
  final slug = video['slug'];
  final title = _text(video['title']);
  final hasId = mediaId is num || mediaId is String;
  if (video['item_type'] != 'video' || !hasId || slug is! String || title == null) return null;
  final place = _Place.of(video, context);
  final kind = _kind(video, context);
  final airDate = _date(video['premiere_date']);
  final images = video['images'] as Map<String, dynamic>? ?? const {};
  final duration = _int(video['duration']);
  return ReplayTitle(
    ref: pbsVideoRef('$mediaId', slug),
    kind: kind,
    title: title,
    summary: _summary(video['description_long'], video['description_short']),
    backdropUrl: _image(images, ['asset-mezzanine-16x9']) ?? _text(video['image']),
    durationSeconds: duration == null || duration <= 0 ? null : duration,
    year: airDate?.year,
    airDate: airDate,
    availableUntil: _date(video['expire_date']),
    availability: pbsVideoAvailability(video, now ?? DateTime.now()),
    seasonNumber: kind == ReplayKind.movie ? null : place.seasonNumber,
    episodeNumber: kind == ReplayKind.episode ? place.episodeNumber : null,
    showRef: place.show,
    showTitle: place.showTitle,
    seasonRef: kind == ReplayKind.movie ? null : place.season,
  );
}

/// Why a video's own record says it cannot be played, or [ReplayAvailability.playable].
///
/// The search index reports `available` for videos that PBS refuses outside the United States, so only the
/// explicit flags and dates are used here. The player page has the final word.
ReplayAvailability pbsVideoAvailability(Map<String, dynamic> video, DateTime now) {
  final flags = video['flags'] as Map? ?? const {};
  if (flags['is_mvod'] == true) return ReplayAvailability.loginRequired;
  final until = _date(video['expire_date']);
  if (until != null && until.isBefore(now)) return ReplayAvailability.expired;
  final from = _date(video['available_date']);
  if (from != null && from.isAfter(now)) return ReplayAvailability.upcoming;
  if (video['availability'] == 'unavailable' || flags['is_playable'] == false) return ReplayAvailability.geoBlocked;
  return ReplayAvailability.playable;
}

/// Where a video sits in its show, read from whichever of the record shapes PBS uses.
class _Place {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;
  final int? episodeNumber;

  const _Place({this.show, this.showTitle, this.season, this.seasonNumber, this.episodeNumber});

  /// Lists give a `parent` (an episode inside a season, or a season for clips). A video page gives a `show` object
  /// with the season and episode numbers.
  factory _Place.of(Map<String, dynamic> video, PbsContext context) {
    final parent = video['parent'] as Map<String, dynamic>?;
    final parentType = parent?['resource_type'];
    final seasonRecord = switch (parentType) {
      'episode' => parent?['season'] as Map<String, dynamic>?,
      'season' => parent,
      _ => null,
    };
    final pageShow = video['show'] as Map<String, dynamic>?;
    final showRecord = seasonRecord?['show'] as Map<String, dynamic>? ?? pageShow;
    final rawSlug = showRecord?['slug'];
    final showSlug = rawSlug is String ? rawSlug : null;
    final seasonCid = seasonRecord?['cid'];
    return _Place(
      show: context.show ?? (showSlug == null ? null : pbsShowRef(showSlug)),
      showTitle: context.showTitle ?? _text(showRecord?['title']),
      season: context.season ?? (showSlug != null && seasonCid is String ? pbsSeasonRef(showSlug, seasonCid) : null),
      seasonNumber: context.seasonNumber ?? _int(seasonRecord?['ordinal']) ?? _int(pageShow?['season']),
      episodeNumber: parentType == 'episode' ? _int(parent?['ordinal']) : _int(pageShow?['episode']),
    );
  }
}

ReplayKind _kind(Map<String, dynamic> video, PbsContext context) {
  final type = video['video_type'];
  if (type == 'clip' || type == 'preview') return ReplayKind.clip;
  final parentType = (video['parent'] as Map?)?['resource_type'];
  final isEpisode = context.inSeason || parentType == 'episode' || video['parent_type'] == 'episode';
  return isEpisode ? ReplayKind.episode : ReplayKind.movie;
}

/// PBS numbers FRONTLINE's seasons by year, so a number that large is shown as the year.
String _seasonName(int ordinal, String? name, {required bool extrasOnly}) {
  final label = ordinal >= 1900 ? '$ordinal' : 'Season $ordinal';
  final named = name == null || name == label ? label : '$label: $name';
  return extrasOnly ? '$named extras' : named;
}

String? _image(Map<String, dynamic> images, List<String> keys) {
  for (final key in keys) {
    final url = images[key];
    if (url is String && url.isNotEmpty) return url;
  }
  return null;
}

String? _summary(Object? long, Object? short) {
  for (final candidate in [long, short]) {
    final text = htmlToText(candidate is String ? candidate : null);
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// The page data marks missing numbers with strings such as `\$undefined`, which are not numbers.
int? _int(Object? value) => value is num ? value.toInt() : null;

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;
