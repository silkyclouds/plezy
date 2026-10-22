import '../../model/replay_ref.dart';

const drtvSourceId = 'drtv';

/// Native ids tell the three levels apart because DR's numeric ids do not: `serie/6954` is a show, `saeson/9008` a
/// season, `serie/6954/alle` the single season of a show that DR does not split, and a bare number a playable item.
ReplayRef drtvShowRef(String showId) => ReplayRef(drtvSourceId, 'serie/$showId');

ReplayRef drtvSeasonRef(String seasonId) => ReplayRef(drtvSourceId, 'saeson/$seasonId');

ReplayRef drtvAllEpisodesRef(String showId) => ReplayRef(drtvSourceId, 'serie/$showId/alle');

ReplayRef drtvPlayableRef(String itemId) => ReplayRef(drtvSourceId, itemId);

sealed class DrtvId {
  const DrtvId();
}

final class DrtvShowId extends DrtvId {
  final String showId;

  const DrtvShowId(this.showId);
}

final class DrtvSeasonId extends DrtvId {
  final String seasonId;

  const DrtvSeasonId(this.seasonId);
}

final class DrtvAllEpisodesId extends DrtvId {
  final String showId;

  const DrtvAllEpisodesId(this.showId);
}

final class DrtvPlayableId extends DrtvId {
  final String itemId;

  const DrtvPlayableId(this.itemId);
}

final _numeric = RegExp(r'^\d+$');
final _showPart = RegExp(r'^serie/(\d+)$');
final _allPart = RegExp(r'^serie/(\d+)/alle$');
final _seasonPart = RegExp(r'^saeson/(\d+)$');

/// Reads a native id produced by the helpers above, or null for anything else.
DrtvId? parseDrtvId(String nativeId) {
  if (_numeric.hasMatch(nativeId)) return DrtvPlayableId(nativeId);
  final show = _showPart.firstMatch(nativeId);
  if (show != null) return DrtvShowId(show.group(1)!);
  final all = _allPart.firstMatch(nativeId);
  if (all != null) return DrtvAllEpisodesId(all.group(1)!);
  final season = _seasonPart.firstMatch(nativeId);
  if (season != null) return DrtvSeasonId(season.group(1)!);
  return null;
}

/// DR resolves pages by the trailing id and ignores the slug, so a fixed one stands in for it.
String drtvShowPath(String showId) => '/serie/x_$showId';

String drtvSeasonPath(String seasonId) => '/saeson/x_$seasonId';
