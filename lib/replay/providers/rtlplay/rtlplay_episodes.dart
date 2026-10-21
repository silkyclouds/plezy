import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'rtlplay_ids.dart';
import 'rtlplay_labels.dart';
import 'rtlplay_mapper.dart';

/// Daily and weekly magazines use the calendar year as their season index.
const _firstYearIndex = 1900;

/// Number shown for a season. Ordinary seasons keep the broadcaster's index; a year index would read
/// as "season 2026", so those seasons are numbered by position and titled with the year.
int rtlPlaySeasonNumber(List<int> indices, int index) {
  if (index < _firstYearIndex) return index;
  final years = indices.where((i) => i >= _firstYearIndex).toList()..sort();
  return years.indexOf(index) + 1;
}

String _seasonName(int index) => index >= _firstYearIndex ? '$index' : 'Saison $index';

/// One season per index of a programme page. Only the season whose episodes the page lists has a known
/// episode count. A page with a season picker but no indices gets a single season so every show has two levels.
List<ReplayTitle> rtlPlaySeasons(Map<String, dynamic> detail, String programme, {String? poster}) {
  final picker = detail['seasonPicker'] as Map<String, dynamic>?;
  if (picker == null) return const [];
  final show = rtlPlayTitleFromDetail(detail, programme, poster: poster);
  final selected = picker['selected'] as Map<String, dynamic>?;
  final selectedIndex = (selected?['index'] as num?)?.toInt();
  final listed = (selected?['episodes'] as List?)?.length;
  final indices = rtlPlaySeasonIndices(detail);
  final all = indices.isEmpty ? [selectedIndex ?? 1] : indices;

  return [
    for (final index in all)
      ReplayTitle(
        ref: rtlPlayRef('$programme/$index'),
        kind: ReplayKind.season,
        title: _seasonName(index),
        posterUrl: show.posterUrl,
        backdropUrl: show.backdropUrl,
        seasonNumber: rtlPlaySeasonNumber(all, index),
        childCount: index == selectedIndex ? listed : null,
        showRef: show.ref,
        showTitle: show.title,
        availability: show.availability,
      ),
  ];
}

/// Episodes of the season a programme page was requested for, in the broadcaster's order
/// (oldest first for series, newest first for magazines).
List<ReplayTitle> rtlPlayEpisodes(Map<String, dynamic> detail, String programme, int season, {String? poster}) {
  final picker = detail['seasonPicker'] as Map<String, dynamic>?;
  final raw = (picker?['selected'] as Map?)?['episodes'];
  if (raw is! List) return const [];
  final show = rtlPlayTitleFromDetail(detail, programme, poster: poster);
  final number = rtlPlaySeasonNumber(rtlPlaySeasonIndices(detail), season);
  final seasonRef = rtlPlayRef('$programme/$season');

  return [
    for (final item in raw.whereType<Map<String, dynamic>>())
      if (item['id'] is String)
        _episode(item, programme: programme, season: season, number: number, show: show, seasonRef: seasonRef),
  ];
}

ReplayTitle _episode(
  Map<String, dynamic> item, {
  required String programme,
  required int season,
  required int number,
  required ReplayTitle show,
  required ReplayRef seasonRef,
}) {
  final id = item['id'] as String;
  final rawTitle = (item['title'] as String?)?.trim() ?? id;
  final labels = rtlPlayLabels(item['labels']);
  final image = item['imageUrl'] as String?;

  return ReplayTitle(
    ref: rtlPlayEpisodeRef(programme, season, id),
    kind: ReplayKind.episode,
    title: stripEpisodePrefix(rawTitle),
    summary: (item['description'] as String?)?.trim(),
    backdropUrl: image,
    durationSeconds: (item['durationSeconds'] as num?)?.toInt() ?? durationOf(labels),
    airDate: frenchDateOf(labelOfKind(labels, 'Date de diffusion')) ?? slashDateOf(rawTitle),
    availability: show.availability,
    seasonNumber: number,
    episodeNumber: (item['index'] as num?)?.toInt() ?? _numberFromTitle(rawTitle),
    showRef: show.ref,
    showTitle: show.title,
    seasonRef: seasonRef,
  );
}

int? _numberFromTitle(String title) => int.tryParse(RegExp(r'^(\d+)\.\s').firstMatch(title)?.group(1) ?? '');
