import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nrktv_ids.dart';
import 'nrktv_images.dart';
import 'nrktv_text.dart';

/// Titles of a search answer. Hits without current on-demand rights cannot be played and are dropped.
///
/// Search shows blocked programmes too and carries no reliable geographic flag; playback and the forecast decide.
List<ReplayTitle> nrkTitlesFromSearch(Map<String, dynamic> body) {
  final seen = <ReplayRef>{};
  return [
    for (final raw in (body['hits'] as List? ?? const []).whereType<Map>())
      if (_titleOf(raw) case final title? when seen.add(title.ref)) title,
  ];
}

ReplayTitle? _titleOf(Map raw) {
  final hit = raw['hit'];
  if (hit is! Map || hit['hasRights'] == false) return null;
  final id = hit['id'];
  final title = (hit['title'] as String? ?? '').trim();
  if (id is! String || id.isEmpty || title.isEmpty) return null;
  final description = nrkPlainText(hit['description'] as String? ?? '');
  final image = nrkImageRef(hit['image']);
  return switch (raw['type']) {
    'serie' => ReplayTitle(
      ref: nrkShowRef(id),
      kind: ReplayKind.show,
      title: title,
      summary: description.isEmpty ? null : description,
      backdropUrl: image,
    ),
    'program' => ReplayTitle(
      ref: nrkProgramRef(id),
      kind: ReplayKind.movie,
      title: title,
      summary: description.isEmpty ? null : description,
      backdropUrl: image,
    ),
    'episode' => _episode(hit, id, title, description, image),
    _ => null,
  };
}

ReplayTitle _episode(Map hit, String id, String title, String description, String? image) {
  final seriesId = hit['seriesId'] as String?;
  final seasonId = hit['seasonId'] as String?;
  final hasShow = seriesId != null && seriesId.isNotEmpty;
  final display = hit['searchHitDisplayTitle'] as String?;
  final number = int.tryParse('${hit['episodeNumber']}');
  return ReplayTitle(
    ref: nrkProgramRef(id),
    kind: ReplayKind.episode,
    title: display != null && display.trim().isNotEmpty ? display.trim() : nrkEpisodeTitle(title, number: number),
    summary: description.isEmpty ? null : description,
    backdropUrl: image,
    seasonNumber: int.tryParse('${hit['seasonNumber']}'),
    episodeNumber: number,
    showRef: hasShow ? nrkShowRef(seriesId) : null,
    showTitle: hit['seriesTitle'] as String?,
    seasonRef: hasShow && seasonId != null && seasonId.isNotEmpty ? nrkSeasonRef(seriesId, seasonId) : null,
  );
}
