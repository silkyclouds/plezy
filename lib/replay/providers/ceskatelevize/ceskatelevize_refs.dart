import '../../model/replay_ref.dart';

const ceskatelevizeSourceId = 'ceskatelevize';

/// Native id of the season that stands for every episode of a show the broadcaster does not split into seasons.
const ceskatelevizeAllEpisodes = '_all';

/// Native ids tell the levels apart because the broadcaster's numeric ids do not: `show-<sidp>` is a show,
/// `show-<sidp>/<seasonId>` a season, `film-<sidp>` a film listed as a card, and `ep-<idec>` an episode.
ReplayRef ceskatelevizeShowRef(String sidp) => ReplayRef(ceskatelevizeSourceId, 'show-$sidp');

ReplayRef ceskatelevizeFilmRef(String sidp) => ReplayRef(ceskatelevizeSourceId, 'film-$sidp');

ReplayRef ceskatelevizeSeasonRef(String sidp, String seasonId) =>
    ReplayRef(ceskatelevizeSourceId, 'show-$sidp/$seasonId');

ReplayRef ceskatelevizeEpisodeRef(String idec) => ReplayRef(ceskatelevizeSourceId, 'ep-$idec');

sealed class CeskaTelevizeId {
  const CeskaTelevizeId();
}

final class CeskaTelevizeShowId extends CeskaTelevizeId {
  final String sidp;

  const CeskaTelevizeShowId(this.sidp);
}

final class CeskaTelevizeFilmId extends CeskaTelevizeId {
  final String sidp;

  const CeskaTelevizeFilmId(this.sidp);
}

final class CeskaTelevizeSeasonId extends CeskaTelevizeId {
  final String sidp;

  /// `season:<hex>`, `group:<hex>` or [ceskatelevizeAllEpisodes].
  final String seasonId;

  const CeskaTelevizeSeasonId(this.sidp, this.seasonId);

  bool get isWholeShow => seasonId == ceskatelevizeAllEpisodes;
}

final class CeskaTelevizeEpisodeId extends CeskaTelevizeId {
  final String idec;

  const CeskaTelevizeEpisodeId(this.idec);
}

final _show = RegExp(r'^show-(\d+)$');
final _film = RegExp(r'^film-(\d+)$');
final _season = RegExp(r'^show-(\d+)/((?:season|group):[0-9a-f]+|_all)$');
final _episode = RegExp(r'^ep-(\d+)$');

/// Reads a native id produced by the helpers above, or null for anything else.
CeskaTelevizeId? parseCeskaTelevizeId(String nativeId) {
  if (_show.firstMatch(nativeId) case final m?) return CeskaTelevizeShowId(m.group(1)!);
  if (_film.firstMatch(nativeId) case final m?) return CeskaTelevizeFilmId(m.group(1)!);
  if (_season.firstMatch(nativeId) case final m?) return CeskaTelevizeSeasonId(m.group(1)!, m.group(2)!);
  if (_episode.firstMatch(nativeId) case final m?) return CeskaTelevizeEpisodeId(m.group(1)!);
  return null;
}
