import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'drtv_access.dart';
import 'drtv_numbering.dart';
import 'drtv_refs.dart';

/// Where an item was found, so episodes and seasons know their show.
class DrtvContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  /// Flags of the show or season, for items that do not carry their own.
  final DrtvAccess? access;

  const DrtvContext({this.show, this.showTitle, this.season, this.seasonNumber, this.access});

  static const none = DrtvContext();
}

/// Turns DR catalogue items into [ReplayTitle]s and remembers each one's access flags in [book].
class DrtvMapper {
  final DrtvAccessBook book;
  final DateTime Function() _now;

  DrtvMapper(this.book, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// One show, season, episode, programme or film. Links, channels and other card types return null.
  ///
  /// [fallbackSeason] numbers a season that DR leaves unnumbered.
  ReplayTitle? title(Map<String, dynamic> item, {DrtvContext context = DrtvContext.none, int? fallbackSeason}) {
    final kind = _kindOf(item['type']);
    final id = item['id']?.toString();
    if (kind == null || id == null || id.isEmpty) return null;

    final ref = _refOf(kind, id);
    final access = drtvAccessOf(item, inherited: context.access);
    book.record(ref, access);

    final numbers = drtvNumbers(item);
    final raw = (item['title'] as String?)?.trim() ?? id;
    final name = kind == ReplayKind.episode ? drtvEpisodeName(item, showTitle: context.showTitle) : null;
    final seasonNumber = numbers.season ?? (kind == ReplayKind.season ? fallbackSeason : context.seasonNumber);
    final images = item['images'] is Map<String, dynamic> ? item['images'] as Map<String, dynamic> : const {};
    final airDate = _date(_custom(item, 'AvailableFrom'));
    final until = _lastEnd(item['offers']);

    return ReplayTitle(
      ref: ref,
      kind: kind,
      title: _titleOf(kind, raw, name, context, seasonNumber),
      subtitle: _subtitleOf(kind, item, context, seasonNumber),
      summary: _nonEmpty(item['description']) ?? _nonEmpty(item['shortDescription']),
      posterUrl: _nonEmpty(images['poster']),
      backdropUrl: _nonEmpty(images['wallpaper']) ?? _nonEmpty(images['tile']),
      durationSeconds: _positive(item['duration']),
      year: _positive(item['releaseYear']),
      genres: _genres(item),
      contentRating: _rating(item),
      airDate: airDate,
      availableUntil: until,
      availability: _availability(access, airDate, until),
      seasonNumber: seasonNumber,
      episodeNumber: kind == ReplayKind.episode ? numbers.episode : null,
      childCount: _childCountOf(kind, item),
      showRef: kind == ReplayKind.show ? null : (context.show ?? _showRefOf(item)),
      showTitle: switch (kind) {
        ReplayKind.show => null,
        ReplayKind.season => context.showTitle ?? raw,
        _ => context.showTitle ?? name?.show,
      },
      seasonRef: kind == ReplayKind.episode ? (context.season ?? _seasonRefOf(item)) : null,
    );
  }

  /// The cards among [items], without repeats and without the card types that cannot be opened.
  List<ReplayTitle> titles(Iterable<Object?> items, {DrtvContext context = DrtvContext.none}) {
    final seen = <ReplayRef>{};
    return [
      for (final raw in items)
        if (raw is Map<String, dynamic>)
          if (title(raw, context: context) case final card? when seen.add(card.ref)) card,
    ];
  }

  ReplayAvailability _availability(DrtvAccess access, DateTime? airDate, DateTime? until) {
    if (access.drm) return ReplayAvailability.drmProtected;
    final now = _now();
    if (until != null && until.isBefore(now)) return ReplayAvailability.expired;
    if (airDate != null && airDate.isAfter(now)) return ReplayAvailability.upcoming;
    return ReplayAvailability.playable;
  }
}

ReplayKind? _kindOf(Object? type) => switch (type) {
  'show' => ReplayKind.show,
  'season' => ReplayKind.season,
  'episode' => ReplayKind.episode,
  'program' || 'movie' => ReplayKind.movie,
  _ => null,
};

ReplayRef _refOf(ReplayKind kind, String id) => switch (kind) {
  ReplayKind.show => drtvShowRef(id),
  ReplayKind.season => drtvSeasonRef(id),
  _ => drtvPlayableRef(id),
};

/// A season inside its show is "Sæson 2024"; a season met on its own (a home row) keeps the show's title.
String _titleOf(ReplayKind kind, String raw, DrtvEpisodeName? name, DrtvContext context, int? seasonNumber) =>
    switch (kind) {
      ReplayKind.episode => name!.name,
      ReplayKind.season when context.show != null => 'Sæson ${seasonNumber ?? ''}'.trim(),
      _ => raw,
    };

String? _subtitleOf(ReplayKind kind, Map<String, dynamic> item, DrtvContext context, int? seasonNumber) =>
    switch (kind) {
      ReplayKind.episode => _nonEmpty(item['tagline']),
      ReplayKind.season when context.show == null && seasonNumber != null => 'Sæson $seasonNumber',
      _ => null,
    };

int? _childCountOf(ReplayKind kind, Map<String, dynamic> item) => switch (kind) {
  ReplayKind.show => _positive(item['availableSeasonCount']),
  ReplayKind.season => _positive(item['availableEpisodeCount']) ?? _positive(item['episodeCount']),
  _ => null,
};

ReplayRef? _showRefOf(Map<String, dynamic> item) {
  final id = item['showId']?.toString();
  return id == null || id.isEmpty ? null : drtvShowRef(id);
}

ReplayRef? _seasonRefOf(Map<String, dynamic> item) {
  final id = item['seasonId']?.toString();
  return id == null || id.isEmpty ? null : drtvSeasonRef(id);
}

Object? _custom(Map<String, dynamic> item, String key) {
  final fields = item['customFields'];
  return fields is Map<String, dynamic> ? fields[key] : null;
}

List<String> _genres(Map<String, dynamic> item) {
  final categories = _custom(item, 'DisplayCategory');
  if (categories is! String) return const [];
  return [
    for (final part in categories.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

final _ageRating = RegExp(r'^MRAM-(\d+)$');

String? _rating(Map<String, dynamic> item) {
  final segment = _custom(item, 'ClassificationRating');
  if (segment is String) {
    final age = int.tryParse(_ageRating.firstMatch(segment)?.group(1) ?? '');
    if (age != null) return '$age+';
    if (segment == 'MRAM-ALL') return 'Alle';
  }
  final classification = item['classification'];
  return classification is Map<String, dynamic> ? _nonEmpty(classification['name']) : null;
}

/// When the last offer ends, or null when any offer is open-ended.
DateTime? _lastEnd(Object? offers) {
  if (offers is! List) return null;
  final ends = <DateTime>[];
  for (final offer in offers.whereType<Map<String, dynamic>>()) {
    final end = _date(offer['endDate']);
    if (end == null) return null;
    ends.add(end);
  }
  return ends.isEmpty ? null : ends.reduce((a, b) => a.isAfter(b) ? a : b);
}

final _extraFraction = RegExp(r'(\.\d{6})\d+');

DateTime? _date(Object? iso) {
  if (iso is! String) return null;
  return DateTime.tryParse(iso.replaceFirstMapped(_extraFraction, (m) => m.group(1)!))?.toUtc();
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _positive(Object? value) {
  final number = value is num ? value.toInt() : null;
  return number != null && number > 0 ? number : null;
}
