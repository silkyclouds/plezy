import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'rtlplay_ids.dart';
import 'rtlplay_labels.dart';

/// Which artwork a catalogue row carries in its `imageUrl`: the shape follows the row, not the item.
enum RtlPlayShape { portrait, landscape }

/// Playback always needs the viewer's own RTL account, whether or not one is signed in yet; only unreleased
/// titles differ.
ReplayAvailability _availability({bool comingSoon = false}) =>
    comingSoon ? ReplayAvailability.upcoming : ReplayAvailability.loginRequired;

/// Maps one teaser of a row, collection or search result. Returns null without a detail id.
///
/// A teaser does not say whether it is a film or a series: a series always carries a season count in its
/// labels, so labels without one mean a film. Search and collection teasers have no labels and fall back to
/// the genre; the detail page settles it when the title is opened.
ReplayTitle? rtlPlayTitleFromTeaser(Map<String, dynamic> teaser, {RtlPlayShape shape = RtlPlayShape.landscape}) {
  final id = teaser['detailId'];
  if (id is! String || id.isEmpty) return null;

  final labels = rtlPlayLabels(teaser['labels']);
  final genre = teaser['genre'] as String?;
  final seasons = seasonCountOf(labels);
  final duration = durationOf(labels);
  final isMovie = seasons == null && (duration != null || genre == 'Film' || labels.isNotEmpty);
  final portrait = shape == RtlPlayShape.portrait;
  final comingSoon = teaser['comingSoon'] as Map<String, dynamic>?;

  return ReplayTitle(
    ref: rtlPlayRef(id),
    kind: isMovie ? ReplayKind.movie : ReplayKind.show,
    title: (teaser['title'] as String?)?.trim() ?? id,
    subtitle: (comingSoon?['fromLabel'] as String?) ?? emphasizedLabel(teaser['labels']),
    summary: _text(teaser['description']),
    posterUrl: (teaser['portraitImageUrl'] as String?) ?? (portrait ? teaser['imageUrl'] as String? : null),
    backdropUrl:
        (teaser['landscapeImageUrl'] as String?) ??
        (portrait ? teaser['heroImageUrl'] as String? : teaser['imageUrl'] as String?),
    logoUrl: teaser['titleArtImageUrl'] as String?,
    durationSeconds: duration,
    year: yearOf(labels),
    genres: _teaserGenres(genre),
    airDate: frenchDateOf(labelOfKind(labels, 'Date de diffusion')),
    availability: _availability(comingSoon: comingSoon != null),
    childCount: seasons,
  );
}

/// Teasers of a row, in the row's order, without repeats and without items that have no detail page.
List<ReplayTitle> rtlPlayTitlesFromTeasers(Object? teasers, {RtlPlayShape shape = RtlPlayShape.landscape}) {
  if (teasers is! List) return const [];
  final seen = <ReplayRef>{};
  return [
    for (final raw in teasers.whereType<Map<String, dynamic>>())
      if (rtlPlayTitleFromTeaser(raw, shape: shape) case final title? when seen.add(title.ref)) title,
  ];
}

RtlPlayShape rtlPlayRowShape(Map<String, dynamic> row) =>
    row['rowType'] == 'SWIMLANE_PORTRAIT' ? RtlPlayShape.portrait : RtlPlayShape.landscape;

/// Rows that hold programme cards. Banners, genre tiles and live channels are not catalogue content.
bool isRtlPlayCardRow(Map<String, dynamic> row) => (row['rowType'] as String? ?? '').startsWith('SWIMLANE_');

/// A programme page as a movie (no season picker) or a show. [poster] is the portrait art seen on a
/// teaser, since the detail page only carries landscape images.
ReplayTitle rtlPlayTitleFromDetail(Map<String, dynamic> detail, String id, {String? poster}) {
  final header = rtlPlayLabels(detail['headerLabels']);
  final picker = detail['seasonPicker'] as Map<String, dynamic>?;
  final indices = _indices(picker);
  final meta = _meta(detail['moreInfo']);
  final background = detail['backgroundImage'] as Map<String, dynamic>?;
  final badge = _firstLabel(detail['badges']);

  return ReplayTitle(
    ref: rtlPlayRef(id),
    kind: picker == null ? ReplayKind.movie : ReplayKind.show,
    title: _titleLabel(detail) ?? id,
    subtitle: badge,
    summary: _text(detail['description']),
    posterUrl: poster,
    backdropUrl:
        (background?['url1280'] as String?) ??
        (detail['backgroundImageUrl'] as String?) ??
        (detail['landscapeTeaserImageUrl'] as String?),
    logoUrl: (detail['title'] as Map?)?['imageUrl'] as String?,
    durationSeconds: (detail['durationSeconds'] as num?)?.toInt() ?? durationOf(header),
    year: yearOf(header),
    genres: meta['Genre'] ?? const [],
    directors: meta['Réalisation'] ?? const [],
    cast: [...?meta['Présentation'], ...?meta['Rôles']],
    contentRating: ratingOf(detail['ratingIcons']),
    availability: _availability(),
    childCount: picker == null ? null : indices.length,
  );
}

String? _titleLabel(Map<String, dynamic> detail) => ((detail['title'] as Map?)?['label'] as String?)?.trim();

/// Season indices offered by a programme page, in the broadcaster's order.
List<int> rtlPlaySeasonIndices(Map<String, dynamic> detail) =>
    _indices(detail['seasonPicker'] as Map<String, dynamic>?);

List<int> _indices(Map<String, dynamic>? picker) {
  final raw = picker?['indices'];
  return [if (raw is List) ...raw.whereType<num>().map((n) => n.toInt())];
}

/// Items of a `moreInfo.meta` block keyed by its label, for example "Genre" or "Rôles".
Map<String, List<String>> _meta(Object? moreInfo) {
  final blocks = (moreInfo is Map ? moreInfo['meta'] : null);
  final result = <String, List<String>>{};
  if (blocks is! List) return result;
  for (final block in blocks.whereType<Map<String, dynamic>>()) {
    final label = block['label'];
    final items = block['items'];
    if (label is! String || items is! List) continue;
    result[label] = [
      for (final item in items.whereType<Map<String, dynamic>>())
        if (item['label'] is String) item['label'] as String,
    ];
  }
  return result;
}

String? _firstLabel(Object? badges) {
  if (badges is! List) return null;
  return badges.whereType<Map<String, dynamic>>().map((b) => b['label']).whereType<String>().firstOrNull;
}

/// "Série" and "Film" name the kind of title, not a genre.
List<String> _teaserGenres(String? genre) => genre == null || genre == 'Série' || genre == 'Film' ? const [] : [genre];

String? _text(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}
