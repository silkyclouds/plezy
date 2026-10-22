// GraphQL documents sent to RÚV. Introspection is off, so these are the exact shapes the web player uses.

/// Fields of a programme shown as a card. Inside a list (a panel or a category) `episodes` holds only the latest
/// episode, whatever limit is asked, so it gives the geo flag but not the episode count; a programme asked for
/// by id returns them all.
const _cardFields = 'programID title foreign_title slug short_description image portrait_image categories{slug title}';
const _cardEpisode = '{id scope rating duration firstrun file_expires}';
const _listCard = '$_cardFields episodes(limit:1)$_cardEpisode';
const _rootCard = '$_cardFields episodes(limit:2)$_cardEpisode';

const _episode =
    'id title description duration firstrun scope file rating file_expires open_subtitles closed_subtitles '
    'subtitles{name value} number image';

/// Number of episodes asked for in one request. RÚV has no paging argument; the largest programme holds under 1,500.
const ruvEpisodeLimit = 3000;

const ruvPanelsQuery =
    r'query($t:Station!,$l:Int){Featured(station:$t){panels(limit:$l){title slug type programs_count programs{'
    '$_listCard}}}}';

const ruvCategoriesQuery = r'query($s:StationSearch!){Category(station:$s){categories{title slug}}}';

const ruvCategoryQuery =
    r'query($s:StationSearch!,$c:String!){Category(station:$s,category:$c){categories{title slug programs{'
    '$_listCard}}}}';

const ruvSearchQuery = r'query($t:SearchQueryType!,$x:String!){Search(type:$t,text:$x){id episodeId title slug}}';

/// One programme with all its episodes, in the order the editors chose.
const ruvProgramQuery =
    r'query($p:Int!){Program(id:$p){programID slug title description short_description foreign_title format image '
    'portrait_image reverse_episode_order categories{slug title} '
    'episodes(order:PROGRAM,limit:$ruvEpisodeLimit){$_episode}}}';

final _episodeId = RegExp(r'^[A-Za-z0-9]{1,16}$');

/// One episode of a programme, fetched by its id. Null when [episodeId] could not be an RÚV episode id, so nothing
/// but a plain token is ever written into a query.
String? ruvEpisodeQuery(String episodeId) {
  if (!_episodeId.hasMatch(episodeId)) return null;
  return r'query($p:Int!){Program(id:$p){programID title image portrait_image '
      'episodes(limit:1,id:{value:["$episodeId"]}){$_episode}}}';
}

/// Cards for several programmes asked for by id, with up to two episodes each: enough to tell a film from a
/// series. Aliases are `a0`, `a1`, ...
String ruvCardsBatchQuery(List<int> programIds) => _batch(programIds, _rootCard);

/// Only the geo flag of each programme's first episode.
String ruvScopeBatchQuery(List<int> programIds) => _batch(programIds, 'episodes(limit:1){scope}');

String _batch(List<int> programIds, String fields) {
  final aliases = [for (var i = 0; i < programIds.length; i++) 'a$i:Program(id:${programIds[i]}){$fields}'];
  return '{${aliases.join(' ')}}';
}

/// The aliased results of a batch query, in the order the ids were asked.
List<Map<String, dynamic>?> ruvBatchResults(Map<String, dynamic> data, int count) => [
  for (var i = 0; i < count; i++) data['a$i'] as Map<String, dynamic>?,
];
