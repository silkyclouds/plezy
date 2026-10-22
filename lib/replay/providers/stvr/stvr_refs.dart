import '../../model/replay_ref.dart';

const stvrSourceId = 'stvr';

final _digits = RegExp(r'^\d+$');
final _episodeId = RegExp(r'^(\d+)-(\d{8})$');

/// A show is a series id: `7993`.
ReplayRef stvrShowRef(Object seriesId) => ReplayRef(stvrSourceId, '$seriesId');

/// A season is `showSeries/seasonSeries`. Seasons of one show are separate series on the broadcaster's side.
ReplayRef stvrSeasonRef(Object showSeries, Object seasonSeries) => ReplayRef(stvrSourceId, '$showSeries/$seasonSeries');

/// An episode is `programId-yyyymmdd`. The broadcaster cannot look a recording up by id, but it can list one day,
/// so the air day travels with the id.
ReplayRef stvrEpisodeRef(int programId, String airDay) =>
    ReplayRef(stvrSourceId, '$programId-${airDay.replaceAll('-', '')}');

bool stvrIsShowId(String nativeId) => _digits.hasMatch(nativeId);

({String show, String season})? stvrParseSeasonId(String nativeId) {
  final parts = nativeId.split('/');
  if (parts.length != 2 || !_digits.hasMatch(parts[0]) || !_digits.hasMatch(parts[1])) return null;
  return (show: parts[0], season: parts[1]);
}

/// The programme id and the air day (`yyyy-mm-dd`) inside an episode id, or null for any other id.
({int programId, String airDay})? stvrParseEpisodeId(String nativeId) {
  final match = _episodeId.firstMatch(nativeId);
  if (match == null) return null;
  final day = match.group(2)!;
  return (
    programId: int.parse(match.group(1)!),
    airDay: '${day.substring(0, 4)}-${day.substring(4, 6)}-${day.substring(6)}',
  );
}
