import '../../model/replay_title.dart';
import 'ted_playlists.dart';
import 'ted_talks.dart';
import 'ted_topics.dart';

/// Rows of the landing page: the latest talks, playlists, then a row for each of the first topics.
Future<List<ReplayRail>> tedHomeRails(TedTalks talks, TedPlaylists playlists) async {
  final results = await Future.wait([
    talks.latest(),
    playlists.list(),
    for (final topic in tedHomeTopics) talks.topic(topic.slug),
  ]);
  return [
    _rail('latest', tedLatestTitle, results[0], tedLatestBrowseId),
    _rail('playlists', tedPlaylistsTitle, results[1], tedPlaylistsBrowseId),
    for (final (i, topic) in tedHomeTopics.indexed)
      _rail('topic/${topic.slug}', topic.title, results[i + 2], tedTopicBrowseId(topic.slug)),
  ].whereType<ReplayRail>().toList();
}

/// The page of one category, which is a single row that opens the full listing.
Future<List<ReplayRail>> tedCategoryRails(TedTalks talks, TedPlaylists playlists, String categoryId) async {
  final topic = tedTopicOfBrowseId(categoryId);
  final (title, page) = switch (categoryId) {
    tedLatestBrowseId => (tedLatestTitle, await talks.latest()),
    tedPlaylistsBrowseId => (tedPlaylistsTitle, await playlists.list()),
    _ when topic != null => (tedTopicLabel(topic), await talks.topic(topic)),
    _ => ('', const ReplayPage(titles: [], totalCount: 0)),
  };
  final rail = _rail(categoryId, title, page, categoryId);
  return rail == null ? const [] : [rail];
}

ReplayRail? _rail(String id, String title, ReplayPage page, String browseId) => page.titles.isEmpty
    ? null
    : ReplayRail(
        id: id,
        title: title,
        titles: page.titles,
        moreBrowseId: page.totalCount > page.titles.length ? browseId : null,
      );
