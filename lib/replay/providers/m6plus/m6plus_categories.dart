import '../../model/replay_title.dart';

/// Browse id of the virtual section that gathers programmes with extracts or podcasts, the only clear streams.
const m6plusFreeBrowseId = 'free';

/// The catalogue API has no route that lists its sections, so the menu is fixed. Numeric ids are folder ids.
const m6plusCategories = [
  ReplayCategory(id: m6plusFreeBrowseId, title: 'Extraits et podcasts'),
  ReplayCategory(id: '8', title: 'Séries'),
  ReplayCategory(id: '232', title: 'Séries réalité'),
  ReplayCategory(id: '10', title: 'Divertissement'),
  ReplayCategory(id: '907', title: 'Cinéma'),
  ReplayCategory(id: '70', title: 'Téléfilms'),
  ReplayCategory(id: '12', title: 'Info et société'),
  ReplayCategory(id: '58', title: 'Sport'),
  ReplayCategory(id: '52', title: 'Jeunesse'),
  ReplayCategory(id: '2996', title: 'Podcasts'),
];

/// Display names of the channels that get their own row on the home page.
const m6plusChannels = {
  'm6replay': 'M6',
  'w9replay': 'W9',
  '6terreplay': '6ter',
  'gulli': 'Gulli',
  'tevareplay': 'Téva',
};
