import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'stvr_images.dart';
import 'stvr_numbering.dart';
import 'stvr_refs.dart';

final _showPath = RegExp(r'/televizia/archiv/(\d+)/\d+');

/// The shows in a site-search response. Articles and radio blocks are ignored.
List<ReplayTitle> stvrShowsFromSiteSearch(Map<String, dynamic> response) {
  final hits = ((response['blocks'] as Map?)?['video_series'] as Map?)?['hits'];
  if (hits is! List) return const [];
  final shows = <ReplayTitle>[];
  for (final hit in hits.whereType<Map<String, dynamic>>()) {
    final seriesId = _showPath.firstMatch(hit['uri'] as String? ?? '')?.group(1);
    final name = stvrParseShowName(htmlToText(hit['name'] as String?));
    if (seriesId == null || name.base.isEmpty) continue;
    final image = stvrAbsoluteImage(hit['thumbnail'] as String?);
    final summary = htmlToText(hit['description'] as String?);
    shows.add(
      ReplayTitle(
        ref: stvrShowRef(seriesId),
        kind: ReplayKind.show,
        title: name.base,
        summary: summary.isEmpty ? null : summary,
        posterUrl: image,
        backdropUrl: image,
      ),
    );
  }
  return shows;
}

/// [shows] in order, without a second show of the same name. A show reachable by two ids shows once.
List<ReplayTitle> stvrDistinctShows(Iterable<ReplayTitle> shows) {
  final seen = <String>{};
  return [
    for (final show in shows)
      if (seen.add(stvrParseShowName(show.title).key)) show,
  ];
}
