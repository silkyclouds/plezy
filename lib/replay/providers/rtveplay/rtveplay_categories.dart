import '../../model/replay_title.dart';

/// Browse id of the newest full-length videos.
const rtveLatestBrowseId = 'latest';

/// RTVE has no endpoint that lists its sections, so the menu is the television channels. Each id is the channel's
/// id in the catalogue, which is also its browse id.
const rtveCategories = [
  ReplayCategory(id: rtveLatestBrowseId, title: 'Última hora'),
  ReplayCategory(id: '748', title: 'La 1'),
  ReplayCategory(id: '310', title: 'La 2'),
  ReplayCategory(id: '350', title: 'Canal 24 Horas'),
  ReplayCategory(id: '417', title: 'Clan'),
  ReplayCategory(id: '450', title: 'Teledeporte'),
  ReplayCategory(id: '50990', title: 'Filmoteca'),
];

/// Channels that get a row of new episodes on the landing page, keyed by the `channelPermalink` videos carry.
const rtveHomeChannels = [
  (permalink: 'la1', title: 'Novedades en La 1'),
  (permalink: 'la2', title: 'Novedades en La 2'),
  (permalink: 'clan', title: 'Novedades en Clan'),
  (permalink: 'teledeporte', title: 'Novedades en Teledeporte'),
  (permalink: '24-horas', title: 'Novedades en Canal 24 Horas'),
  (permalink: 'archivo-rtve', title: 'Del archivo de RTVE'),
];

final _channelId = RegExp(r'^\d+$');

bool isRtveChannelId(String browseId) => _channelId.hasMatch(browseId);
