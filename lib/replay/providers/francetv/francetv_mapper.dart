import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'francetv_images.dart';
import 'francetv_numbering.dart';
import 'francetv_refs.dart';

/// Where an item was found, so an episode knows its show and season.
class FranceTvContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;

  /// Overrides the season number of the item, for episodes listed under a season row.
  final int? seasonNumber;

  const FranceTvContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = FranceTvContext();
}

/// Last known rights verdict for a video, or null when it was never checked.
typedef FranceTvVerdictLookup = ReplayAvailability? Function(String streamId);

const _portraitTypes = ['vignette_2x3', 'vignette_3x4'];
const _landscapeTypes = ['vignette_16x9', 'background_16x9', 'lt_16x9'];

/// Row types that carry no title cards a replay client can open.
const _skippedRows = {'link', 'live', 'regions', 'playlist_categories', 'playlist_sous_categories'};

/// Turns catalogue items and rows into neutral titles.
class FranceTvMapper {
  final DateTime Function() _clock;
  final FranceTvVerdictLookup? _verdictFor;

  const FranceTvMapper({this._clock = DateTime.now, this._verdictFor});

  /// The same mapping with another source of rights verdicts.
  FranceTvMapper withVerdicts(FranceTvVerdictLookup lookup) => FranceTvMapper(clock: _clock, verdictFor: lookup);

  /// One item of a row, or null for the kinds a replay client cannot open: collections, events,
  /// categories, trailers, live feeds and clips.
  ReplayTitle? title(Map<String, dynamic> item, {FranceTvContext context = FranceTvContext.none}) {
    return switch (item['type']) {
      'program' => show(item),
      'integrale' || 'unitaire' => video(item, context: context),
      _ => null,
    };
  }

  /// A programme as a show, or null when it has no path or no replay episode.
  ReplayTitle? show(Map<String, dynamic> item) {
    final path = item['program_path'] as String?;
    if (path == null || path.isEmpty || item['integral_counter'] == 0) return null;
    final ageMin = item['age_min'];
    return ReplayTitle(
      ref: franceTvShowRef(path),
      kind: ReplayKind.show,
      title: (item['label'] as String?)?.trim() ?? path,
      subtitle: _nonEmpty(item['headline_title']),
      summary: _firstText([item['description'], item['synopsis'], item['headline_title']]),
      posterUrl: franceTvImageReference(item['images'], _portraitTypes),
      backdropUrl: franceTvImageReference(item['images'], _landscapeTypes),
      logoUrl: franceTvImageReference(item['images'], const ['logo']),
      genres: _genres(item),
      directors: franceTvPeople(item['director']),
      cast: franceTvPeople(item['casting']),
      contentRating: ageMin is num && ageMin > 0 ? '${ageMin.toInt()}+' : null,
      childCount: (item['number_of_seasons'] as num?)?.toInt(),
    );
  }

  /// An `integrale` or `unitaire` item as an episode (it belongs to a programme or is numbered) or a movie.
  ReplayTitle? video(Map<String, dynamic> item, {FranceTvContext context = FranceTvContext.none}) {
    final streamId = item['si_id'] as String?;
    if (streamId == null || streamId.isEmpty) return null;
    final program = item['program'] as Map<String, dynamic>?;
    final numbers = franceTvNumbers(item);
    final isEpisode =
        item['type'] == 'integrale' && (program != null || numbers.season != null || numbers.episode != null);
    final showPath = program?['program_path'] as String?;
    final landscape = franceTvImageReference(item['images'], _landscapeTypes);

    return ReplayTitle(
      ref: franceTvVideoRef(streamId, (item['id'] as num?)?.toInt()),
      kind: isEpisode ? ReplayKind.episode : ReplayKind.movie,
      title: (item['title'] as String?)?.trim() ?? streamId,
      subtitle: _nonEmpty(item['headline_title']),
      summary: _firstText([item['description'], item['headline_title']]),
      posterUrl: isEpisode ? landscape : franceTvImageReference(item['images'], _portraitTypes) ?? landscape,
      backdropUrl: landscape,
      durationSeconds: _duration(item['duration']),
      year: (item['production_year'] as num?)?.toInt(),
      genres: _genres(item),
      directors: franceTvPeople(item['director']),
      cast: franceTvPeople(item['casting']),
      contentRating: _rating(item['rating_csa_code']),
      airDate: _epoch(item['broadcast_begin_date']) ?? _epoch(item['begin_date']),
      availableUntil: _epoch(item['end_date']),
      availability: _availability(item, streamId),
      seasonNumber: isEpisode ? context.seasonNumber ?? numbers.season : null,
      episodeNumber: isEpisode ? numbers.episode : null,
      showRef: isEpisode ? context.show ?? (showPath == null ? null : franceTvShowRef(showPath)) : null,
      showTitle: isEpisode ? (context.showTitle ?? program?['label'] as String?) : null,
      seasonRef: isEpisode ? context.season : null,
    );
  }

  /// The titles of one row, without repeats.
  List<ReplayTitle> titles(Iterable<Object?> items, {FranceTvContext context = FranceTvContext.none}) {
    final seen = <ReplayRef>{};
    return [
      for (final raw in items)
        if (raw is Map<String, dynamic>)
          if (title(raw, context: context) case final t? when seen.add(t.ref)) t,
    ];
  }

  /// Rows of a page. Personalised, live and navigation rows, and rows left empty, are dropped.
  /// [programsBrowseId] is what "see all" opens for the rows that list programmes.
  List<ReplayRail> rails(Map<String, dynamic> page, {String? programsBrowseId}) {
    final rows = page['collections'];
    if (rows is! List) return const [];
    final rails = <ReplayRail>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map<String, dynamic> || _skippedRows.contains(row['type'])) continue;
      final titles = this.titles(row['items'] as List? ?? const []);
      if (titles.isEmpty) continue;
      rails.add(
        ReplayRail(
          id: '${row['id'] ?? '${row['type']}_$i'}',
          title: (row['label'] as String?)?.trim() ?? '',
          titles: titles,
          moreBrowseId: row['type'] == 'playlist_program' ? programsBrowseId : null,
        ),
      );
    }
    return rails;
  }

  ReplayAvailability _availability(Map<String, dynamic> item, String streamId) {
    final now = _clock();
    final end = _epoch(item['end_date']);
    if (end != null && end.isBefore(now)) return ReplayAvailability.expired;
    final begin = _epoch(item['begin_date']);
    if (begin != null && begin.isAfter(now)) return ReplayAvailability.upcoming;
    return _verdictFor?.call(streamId) ?? ReplayAvailability.playable;
  }
}

String? _nonEmpty(Object? value) {
  final text = htmlToText(value is String ? value : null);
  return text.isEmpty ? null : text;
}

String? _firstText(List<Object?> candidates) {
  for (final candidate in candidates) {
    final text = _nonEmpty(candidate);
    if (text != null) return text;
  }
  return null;
}

DateTime? _epoch(Object? seconds) =>
    seconds is num ? DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000, isUtc: true) : null;

/// The live feed placeholder reports years of duration; anything over a day is not a real length.
int? _duration(Object? seconds) => seconds is num && seconds > 0 && seconds <= 86400 ? seconds.toInt() : null;

String? _rating(Object? code) {
  if (code is! String || code.isEmpty) return null;
  final age = int.tryParse(code);
  return age == null ? code : '$age+';
}

List<String> _genres(Map<String, dynamic> item) {
  final labels = <String>[];
  final categories = item['categories'];
  if (categories is List) {
    labels.addAll(categories.whereType<Map<String, dynamic>>().map((c) => c['label']).whereType<String>());
  }
  final category = (item['category'] as Map?)?['label'];
  if (labels.isEmpty && category is String) labels.add(category);
  return [
    for (final label in labels)
      if (label.trim().isNotEmpty) '${label.trim()[0].toUpperCase()}${label.trim().substring(1)}',
  ];
}

/// Splits a credits string. Credits come as one comma separated string, sometimes joined by "et" and cut with an ellipsis.
List<String> franceTvPeople(Object? names) {
  if (names is! String) return const [];
  return [
    for (final part in names.split(RegExp(r',|\bet\b')))
      if (part.replaceAll('…', '').trim().isNotEmpty) part.replaceAll('…', '').trim(),
  ];
}
