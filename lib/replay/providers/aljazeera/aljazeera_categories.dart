import '../../model/replay_title.dart';

/// Browse id of the programme list of the "TV shows" section and of its GraphQL category.
const aljazeeraShowsCategory = 'tv-shows';
const aljazeeraDocumentariesCategory = 'documentary';

/// Browse id of the short news clips feed. It is also the programme slug the site uses for it.
const aljazeeraClipsBrowseId = 'newsfeed';

/// Prefix of the browse id that lists the episodes of one programme, newest first.
const aljazeeraProgrammeBrowsePrefix = 'p:';

const aljazeeraCategories = [
  ReplayCategory(id: aljazeeraShowsCategory, title: 'TV shows'),
  ReplayCategory(id: aljazeeraDocumentariesCategory, title: 'Documentaries'),
  ReplayCategory(id: aljazeeraClipsBrowseId, title: 'Newsfeed'),
];

/// Programmes whose latest episodes open the landing page, as `(slug, row title)`.
const aljazeeraHomeProgrammes = [
  ('inside-story', 'Inside Story'),
  ('the-listening-post', 'The Listening Post'),
  ('fault-lines', 'Fault Lines'),
  ('101-east', '101 East'),
];
