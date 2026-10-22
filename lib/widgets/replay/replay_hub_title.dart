import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_hub.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../replay/suggestions/replay_home_suggestions.dart';
import '../replay_channel_logo.dart';

/// Title of a catch-up suggestion row on the home screen: the channel's logo, then the row's name.
///
/// Screen readers hear "Documentaires sur ARTE" as one title. Rows that are not suggestions keep their usual title.
class ReplayHubTitle extends StatelessWidget {
  final MediaHub hub;
  final TextStyle? style;

  /// Scales the logo with the rest of the row header on large screens.
  final double scale;

  const ReplayHubTitle({super.key, required this.hub, this.style, this.scale = 1});

  static bool appliesTo(MediaHub hub) => ReplayHomeSuggestions.isSuggestion(hub);

  @override
  Widget build(BuildContext context) {
    final sourceId = hub.libraryId ?? '';
    final channel = replaySourceName(sourceId);
    return Semantics(
      header: true,
      label: t.replay.homeRow.label(row: hub.title, channel: channel),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReplayChannelLogo.inline(
              sourceId: sourceId,
              name: channel,
              height: ReplayChannelLogo.inlineHeight * scale,
              maxWidth: ReplayChannelLogo.inlineMaxWidth * scale,
              color: style?.color,
              textStyle: style,
            ),
            SizedBox(width: 8 * scale),
            Flexible(child: Text(hub.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          ],
        ),
      ),
    );
  }
}
