import '../../model/replay_title.dart';
import 'drtv_api.dart';
import 'drtv_mapper.dart';

/// The cards of a search answer: shows first, then films, then single episodes and programmes. Groups for people,
/// teams, events and live channels are not content this app can open.
List<ReplayTitle> drtvSearchResults(DrtvJson body, DrtvMapper mapper) {
  final cards = <Object?>[];
  for (final group in const ['series', 'movies', 'playable']) {
    final block = body[group];
    final items = block is DrtvJson ? block['items'] : null;
    if (items is List) cards.addAll(items);
  }
  return mapper.titles(cards);
}
