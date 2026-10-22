import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';

/// A topic page of ted.com. The API has no topic list and no topic names, so the menu is fixed.
class TedTopic {
  final String slug;
  final String title;

  const TedTopic(this.slug, this.title);
}

const tedTopics = [
  TedTopic('technology', 'Technology'),
  TedTopic('science', 'Science'),
  TedTopic('design', 'Design'),
  TedTopic('global+issues', 'Global issues'),
  TedTopic('business', 'Business'),
  TedTopic('culture', 'Culture'),
  TedTopic('entertainment', 'Entertainment'),
  TedTopic('health', 'Health'),
  TedTopic('psychology', 'Psychology'),
  TedTopic('education', 'Education'),
  TedTopic('art', 'Art'),
  TedTopic('society', 'Society'),
  TedTopic('environment', 'Environment'),
  TedTopic('innovation', 'Innovation'),
];

/// Topics shown as rows on the landing page.
final tedHomeTopics = tedTopics.take(4).toList();

/// The latest talks are the whole catalogue, newest first.
const tedLatestBrowseId = replayAllBrowseId;
const tedPlaylistsBrowseId = 'playlists';
const tedLatestTitle = 'Latest talks';
const tedPlaylistsTitle = 'Playlists';
const _topicPrefix = 'topic/';

String tedTopicBrowseId(String slug) => '$_topicPrefix$slug';

/// The topic slug a browse id points at, or null when it is not a topic.
String? tedTopicOfBrowseId(String browseId) =>
    browseId.startsWith(_topicPrefix) && browseId.length > _topicPrefix.length
    ? browseId.substring(_topicPrefix.length)
    : null;

const _labelOverrides = {'ted+ed': 'TED-Ed', 'tedx': 'TEDx', 'ai': 'AI', 'ted+fellows': 'TED Fellows'};

/// A readable name for a topic slug such as `climate+change`.
String tedTopicLabel(String slug) {
  for (final topic in tedTopics) {
    if (topic.slug == slug) return topic.title;
  }
  final override = _labelOverrides[slug];
  if (override != null) return override;
  final spaced = slug.replaceAll('+', ' ').trim();
  return spaced.isEmpty ? slug : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

List<ReplayCategory> tedCategories() => [
  const ReplayCategory(id: tedLatestBrowseId, title: tedLatestTitle),
  const ReplayCategory(id: tedPlaylistsBrowseId, title: tedPlaylistsTitle),
  for (final topic in tedTopics) ReplayCategory(id: tedTopicBrowseId(topic.slug), title: topic.title),
];
