import '../../model/replay_title.dart';
import 'zdfmediathek_mapper.dart';
import 'zdfmediathek_text.dart';

/// Row types that hold content. The others are personal ("Mein Programm"), promotional, filled by a separate
/// recommendation call, or the tile list of the category page.
const zdfContentRows = {'teaser', 'teaserPoster', 'teaserContent'};

/// Titles of a list of teasers, without trailers, without what cannot be opened and without repeats.
List<ReplayTitle> zdfTitles(ZdfMapper mapper, Iterable<Object?> teasers) {
  final seen = <Object>{};
  return [
    for (final raw in teasers)
      if (raw is Map<String, dynamic> && raw['currentVideoType'] != 'trailer')
        if (mapper.title(raw) case final title? when seen.add(title.ref)) title,
  ];
}

/// The rows of a home or category page: the editorial stage first, then each cluster that has something to play.
List<ReplayRail> zdfRails(ZdfMapper mapper, Map<String, dynamic> page) {
  final rails = <ReplayRail>[];
  void add(String id, String name, Object? teasers) {
    if (teasers is! List) return;
    final titles = zdfTitles(mapper, teasers);
    if (titles.isNotEmpty) rails.add(ReplayRail(id: id, title: name, titles: titles));
  }

  add('stage', 'Empfohlen', page['stage']);
  final clusters = page['cluster'];
  if (clusters is! List) return rails;
  for (var i = 0; i < clusters.length; i++) {
    final cluster = clusters[i];
    if (cluster is! Map<String, dynamic> || !zdfContentRows.contains(cluster['type'])) continue;
    final name = zdfText(cluster['name']) ?? '';
    add('row$i:$name', name, cluster['teaser']);
  }
  return rails;
}

/// The sections listed by the categories overview.
List<ReplayCategory> zdfCategories(Map<String, dynamic> overview) {
  final clusters = overview['cluster'];
  if (clusters is! List) return const [];
  return [
    for (final cluster in clusters.whereType<Map<String, dynamic>>())
      for (final teaser in (cluster['teaser'] as List? ?? const []).whereType<Map<String, dynamic>>())
        if (teaser['type'] == 'category' && teaser['id'] is String)
          ReplayCategory(id: teaser['id'] as String, title: zdfText(teaser['titel']) ?? teaser['id'] as String),
  ];
}

/// Every show of the A to Z page, in alphabetical order.
List<ReplayTitle> zdfAlphabeticalShows(ZdfMapper mapper, Map<String, dynamic> page) {
  final clusters = page['cluster'];
  if (clusters is! List) return const [];
  return zdfTitles(mapper, [
    for (final cluster in clusters.whereType<Map<String, dynamic>>()) ...(cluster['teaser'] as List? ?? const []),
  ]);
}
