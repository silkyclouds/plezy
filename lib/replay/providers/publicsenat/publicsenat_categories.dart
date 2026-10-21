import '../../model/replay_title.dart';

const publicSenatLatestBrowseId = 'replays';
const publicSenatProgrammesBrowseId = 'programmes';
const publicSenatDocumentariesBrowseId = 'documentaires';

/// Slug of the programme that holds the channel's standalone documentaries.
const publicSenatDocumentarySlug = 'documentaire';

const publicSenatCategories = [
  ReplayCategory(id: publicSenatLatestBrowseId, title: 'Derniers replays'),
  ReplayCategory(id: publicSenatProgrammesBrowseId, title: 'Programmes'),
  ReplayCategory(id: publicSenatDocumentariesBrowseId, title: 'Documentaires'),
];
