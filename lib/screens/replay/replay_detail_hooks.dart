import 'package:flutter/widgets.dart';

import '../../media/media_item.dart';
import 'replay_detail_info_line.dart';
import 'replay_detail_tint.dart';

export 'replay_detail_actions.dart' show ReplayActionRowSpec, replayDetailActionRow;
export 'replay_detail_focus.dart' show replayActionRowTakesFocus, replayInitialEpisodeId;

/// Greys and dims [artwork] on the detail page of a catch-up title that cannot be played; any other page is untouched.
Widget replayTinted(MediaItem page, List<MediaItem> episodes, Widget artwork) =>
    ReplayUnavailableTint(page: page, episodes: episodes, child: artwork);

/// Like [replayTinted] for the show's logo, which is text when the show has none and must keep its ink then.
Widget replayTintedLogo(MediaItem page, List<MediaItem> episodes, Widget logo) =>
    ReplayUnavailableTint(page: page, episodes: episodes, enabled: page.clearLogoPath != null, child: logo);

/// The information line of a detail page. A catch-up title gets its channel's logo in front of [fields]; any other
/// title gets [fields] as they are.
Widget replayInfoLine(MediaItem item, TextStyle style, Widget? fields) => item.backend.isReplay
    ? ReplayDetailInfoLine(item: item, textStyle: style, rest: fields)
    : fields ?? const SizedBox.shrink();
