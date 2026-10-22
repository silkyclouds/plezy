import 'package:flutter/material.dart';

import '../../media/media_item.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../widgets/fitted_metadata_line.dart';
import '../../widgets/replay_channel_logo.dart';
import 'replay_blocking.dart';
import 'replay_logo_presence.dart';

/// The start of a detail page's information line for a catch-up title: the channel's logo in place of its name, then
/// the usual bullet and the rest of the line. The name in the line's own style stands in when there is no logo.
class ReplayDetailInfoLine extends StatelessWidget {
  final MediaItem item;
  final TextStyle textStyle;

  /// The remaining fields of the line, already fitted; null when there are none.
  final Widget? rest;

  const ReplayDetailInfoLine({super.key, required this.item, required this.textStyle, this.rest});

  @override
  Widget build(BuildContext context) {
    final sourceId = replaySourceIdOf(item) ?? '';
    final name = item.studio ?? replaySourceName(sourceId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Channel(sourceId: sourceId, name: name, textStyle: textStyle),
        if (rest != null) ...[
          Text(FittedMetadataLine.separator, maxLines: 1, style: textStyle),
          Flexible(child: rest!),
        ],
      ],
    );
  }
}

class _Channel extends StatelessWidget {
  final String sourceId;
  final String name;
  final TextStyle textStyle;

  const _Channel({required this.sourceId, required this.name, required this.textStyle});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: replayLogoIsBundled(sourceId),
      builder: (context, snapshot) {
        if (snapshot.data == false) return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle);
        return ReplayChannelLogo.inline(sourceId: sourceId, name: name, color: textStyle.color, textStyle: textStyle);
      },
    );
  }
}
