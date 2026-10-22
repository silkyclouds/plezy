import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'err_images.dart';
import 'err_mapper.dart';
import 'err_numbering.dart';
import 'err_refs.dart';
import 'err_season_list.dart';

/// A far-off end of a rights window means "no end"; ERR uses years like 2105 or 2297 for archive items.
const _openEndedYears = 10;

/// The show and season an episode page belongs to, read from the page's own season list.
ErrContext errPageContext(Map<String, dynamic> page) {
  final main = page['mainContent'];
  if (main is! Map<String, dynamic>) return ErrContext.none;
  final root = (main['rootContentId'] as num?)?.toInt() ?? 0;
  if (root <= 0) return ErrContext.none;
  final list = errParseSeasonList(page['seasonList']);
  final key = list == null ? 1 : _seasonKey(page, main, list);
  return ErrContext(
    show: errRef(root),
    showTitle: _showName(main),
    season: key == null ? null : errSeasonRef(root, key),
    seasonNumber: key,
  );
}

int? _seasonKey(Map<String, dynamic> page, Map<String, dynamic> main, ErrSeasonList list) {
  final active = ErrSeasonList.activeKey(page['seasonList']);
  if (active != null) return active;
  final number = (main['season'] as num?)?.toInt();
  return number != null && list.entry(number) != null ? number : null;
}

String _showName(Map<String, dynamic> main) {
  final root = main['rootContent'];
  return errText(root is Map ? root['heading'] : null) ??
      errText(main['statsSeriesTitle']) ??
      errText(main['heading']) ??
      '';
}

/// The film, episode or clip a content page is about, or null when the page has no video (an article) or ERR no
/// longer serves one.
ReplayTitle? errTitleFromPage(Map<String, dynamic> page, {DateTime? now}) {
  final main = page['mainContent'];
  if (main is! Map<String, dynamic>) return null;
  final media = errFirstMedia(main);
  final kind = switch (main['type']) {
    'episode' => ReplayKind.episode,
    'clip' => ReplayKind.clip,
    'movie' || 'show' => ReplayKind.movie,
    _ => null,
  };
  final id = (main['id'] as num?)?.toInt();
  if (media == null || kind == null || id == null) return null;

  final context = kind == ReplayKind.movie ? ErrContext.none : errPageContext(page);
  final heading = errText(main['heading']) ?? '$id';
  final subHeading = errText(main['subHeading']);
  final isEpisode = kind == ReplayKind.episode;
  final backdrop = errBackdropReference(main);
  return ReplayTitle(
    ref: errRef(id),
    kind: kind,
    title: isEpisode ? subHeading ?? heading : heading,
    subtitle: isEpisode ? null : subHeading,
    summary: _summary(main),
    posterUrl: errPosterReference(main) ?? backdrop,
    backdropUrl: backdrop,
    durationSeconds: errDuration(media),
    year: int.tryParse('${main['year']}'),
    genres: _genres(page['category']),
    directors: _credits(main, (type) => type.startsWith('režissöör') || type.startsWith('lavastaja')),
    cast: _credits(main, (type) => const ['näitleja', 'näitlejad', 'osatäitjad', 'esinejad'].contains(type)),
    airDate: errDate(main['publicStart']),
    availableUntil: errAvailableUntil(media, now ?? DateTime.now()),
    availability: _isDrm(media) ? ReplayAvailability.drmProtected : ReplayAvailability.playable,
    seasonNumber: isEpisode ? context.seasonNumber ?? _number(main['season']) : null,
    episodeNumber: isEpisode ? _number(main['episode']) ?? errEpisodeFromTitle(heading, subHeading) : null,
    showRef: context.show,
    showTitle: context.showTitle,
    seasonRef: context.season,
  );
}

/// The programme behind a content page opened on a series or show id. ERR answers such an id with the programme's
/// first episode and the programme itself in `rootContent`.
ReplayTitle? errShowFromPage(Map<String, dynamic> page, int showId, {int? seasonCount}) {
  final main = page['mainContent'];
  if (main is! Map<String, dynamic>) return null;
  final root = main['rootContent'];
  final programme = root is Map<String, dynamic> ? root : const <String, dynamic>{};
  final fallback = errBackdropReference(main);
  final backdrop = errBackdropReference(programme) ?? fallback;
  return ReplayTitle(
    ref: errRef(showId),
    kind: ReplayKind.show,
    title: _showName(main),
    summary: _summary(programme),
    posterUrl: errPosterReference(programme) ?? backdrop,
    backdropUrl: backdrop,
    genres: _genres(page['category']),
    childCount: seasonCount,
  );
}

String? _summary(Map<String, dynamic> item) {
  for (final key in const ['body', 'lead']) {
    final text = htmlToText(item[key] as String?).replaceAll(' ', ' ').trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

int? _number(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number == null || number <= 0 ? null : number;
}

List<String> _genres(Object? categories) {
  if (categories is! List) return const [];
  final names = <String>{for (final category in categories.whereType<Map>()) ?errText(category['name'])};
  return names.toList();
}

List<String> _credits(Map<String, dynamic> main, bool Function(String type) matches) {
  final makers = main['makers'];
  if (makers is! List) return const [];
  final names = <String>{
    for (final maker in makers.whereType<Map>())
      if (matches('${maker['type']}'.toLowerCase()) && errText(maker['name']) != null) errText(maker['name'])!,
  };
  return names.toList();
}

/// Whether the media is DRM protected, by ERR's flag or by the `drm` folder its stream addresses live in.
bool _isDrm(Map<String, dynamic> media) => (media['restrictions'] as Map?)?['drm'] == true || media['folder'] == 'drm';

/// The end of the rights window that covers [now], or null when there is none or it is open-ended.
DateTime? errAvailableUntil(Map<String, dynamic> media, DateTime now) {
  final periods = media['periods'];
  if (periods is! List) return null;
  final limit = now.add(const Duration(days: 365 * _openEndedYears));
  DateTime? latest;
  for (final period in periods.whereType<Map>()) {
    final start = errDate(period['publicStart']);
    final end = errDate(period['publicEnd']);
    if (start == null || end == null || start.isAfter(now) || !end.isAfter(now)) continue;
    if (latest == null || end.isAfter(latest)) latest = end;
  }
  return latest == null || latest.isAfter(limit) ? null : latest;
}
