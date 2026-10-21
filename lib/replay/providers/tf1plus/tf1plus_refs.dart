import '../../model/replay_ref.dart';

const tf1SourceId = 'tf1plus';

/// Native id of the season that stands for every replay of a show that has no season lists.
const tf1AllEpisodesSeason = '_all';

/// Native ids are of three shapes, told apart by form alone:
/// a programme slug (`hpi`), a season (`hpi/611169bd645161a2`, or `hpi/_all`) and a video UUID.
ReplayRef tf1Ref(String nativeId) => ReplayRef(tf1SourceId, nativeId);

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

bool tf1IsVideoId(String nativeId) => _uuid.hasMatch(nativeId);

bool tf1IsSeasonId(String nativeId) => nativeId.contains('/');

ReplayRef tf1SeasonRef(String programSlug, String listId) => tf1Ref('$programSlug/$listId');

({String programSlug, String listId}) tf1SplitSeasonId(String nativeId) {
  final cut = nativeId.indexOf('/');
  return (programSlug: nativeId.substring(0, cut), listId: nativeId.substring(cut + 1));
}
