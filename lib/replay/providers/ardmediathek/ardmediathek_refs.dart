import '../../model/replay_ref.dart';
import 'ardmediathek_json.dart';

const ardMediathekSourceId = 'ardmediathek';

/// Native id of the season that stands for every video of a show that has no numbered seasons.
const ardAllVideosSeason = 'all';

ReplayRef ardItemRef(String id) => ReplayRef(ardMediathekSourceId, 'item/$id');

ReplayRef ardShowRef(String id) => ReplayRef(ardMediathekSourceId, 'show/$id');

ReplayRef ardSeasonRef(String showId, String season) => ReplayRef(ardMediathekSourceId, 'show/$showId/$season');

/// What a native id points at.
sealed class ArdTarget {
  const ArdTarget();
}

final class ArdItemTarget extends ArdTarget {
  final String id;
  const ArdItemTarget(this.id);
}

final class ArdShowTarget extends ArdTarget {
  final String id;
  const ArdShowTarget(this.id);
}

/// [season] is a season number or [ardAllVideosSeason].
final class ArdSeasonTarget extends ArdTarget {
  final String showId;
  final String season;
  const ArdSeasonTarget(this.showId, this.season);
}

/// Reads a native id back. Ids from other sources and malformed ids give null.
ArdTarget? ardTarget(ReplayRef ref) {
  if (ref.source != ardMediathekSourceId) return null;
  final parts = ref.nativeId.split('/');
  if (parts.any((part) => part.isEmpty)) return null;
  return switch (parts) {
    ['item', final id] => ArdItemTarget(id),
    ['show', final id] => ArdShowTarget(id),
    ['show', final id, final season] => ArdSeasonTarget(id, season),
    _ => null,
  };
}

/// Where a teaser leads: `item` for a video, `grouping` for a show, `editorial` for a page.
typedef ArdLink = ({String kind, String id});

/// The page a teaser opens, read from `links.target.href` (`.../pages/{partner}/{kind}/{id}`).
///
/// The partner segment is ignored on purpose: the gateway answers the same for any partner.
ArdLink? ardLinkTarget(Map<String, dynamic> teaser) {
  final href = ardText(ardMap(ardMap(teaser['links'])?['target'])?['href']);
  if (href == null) return null;
  final segments = Uri.tryParse(href)?.pathSegments;
  final at = segments?.indexOf('pages') ?? -1;
  if (segments == null || at < 0 || segments.length < at + 4) return null;
  return (kind: segments[at + 2], id: segments[at + 3]);
}
