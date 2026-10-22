import 'package:flutter/material.dart';

import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../backend_badge.dart';
import '../replay_channel_logo.dart';
import 'replay_channel_of.dart';

/// The origin line of a catch-up search result: the source icon and "Catch-up TV", then the broadcaster's logo in
/// place of its name.
class ReplaySourceLine extends StatelessWidget {
  static const height = 22.0;
  static const _gap = 8.0;
  static const _fontSize = 15.0;

  final MediaItem item;

  /// The broadcaster as the list labels it; null when the list does not name libraries.
  final String? libraryName;

  const ReplaySourceLine({super.key, required this.item, required this.libraryName});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(color: color, fontSize: _fontSize, height: 1.2);
    final channel = libraryName == null ? null : replayChannelOf(item);
    final serverName = item.serverName;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          BackendBadge(backend: MediaBackend.replay, size: 16, color: color),
          if (serverName != null) ...[
            const SizedBox(width: _gap),
            Flexible(
              child: Text(serverName, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          ],
          if (channel != null) ...[
            const SizedBox(width: _gap),
            Text('•', style: style),
            const SizedBox(width: _gap),
            Flexible(
              child: ReplayChannelLogo.inline(
                sourceId: channel.sourceId,
                name: channel.name,
                color: color,
                textStyle: style,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
