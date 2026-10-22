import '../../model/replay_title.dart';

const dwProgrammesCategory = 'programmes';

/// Browse id of the newest videos across every programme.
const dwLatestBrowseId = 'latest';

/// DW has no section list for its video catalogue, so the menu is fixed.
const dwCategories = [
  ReplayCategory(id: dwProgrammesCategory, title: 'Programmes'),
  ReplayCategory(id: dwLatestBrowseId, title: 'Latest videos'),
];

/// Programmes that get their own row on the landing page: documentaries, news, culture and science.
const dwFlagshipProgrammes = [294010, 262267, 877843, 66947984];
