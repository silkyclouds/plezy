import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../providers/download_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/focusable_media_card.dart';
import '../../widgets/replay_channel_logo.dart';
import '../libraries/state_messages.dart';
import '../main_screen.dart';
import 'downloads_options.dart';
import 'replay_downloads_grouping.dart';

/// The Catch-up TV tab of the Downloads screen: one header per broadcaster, each followed by its grid of cards.
///
/// The tab has no grouping, filter or sort chips; the per-broadcaster sections replace them. Headers never take
/// focus, so Up and Down move from card to card across sections.
class ReplayDownloadsTab extends StatefulWidget {
  static const cardSize = Size(294, 165);
  static const gap = 16.0;
  static const headerHeight = 32.0;

  final bool isActive;
  final VoidCallback? onBack;

  const ReplayDownloadsTab({super.key, required this.isActive, this.onBack});

  @override
  State<ReplayDownloadsTab> createState() => ReplayDownloadsTabState();
}

class ReplayDownloadsTabState extends State<ReplayDownloadsTab>
    with AutomaticKeepAliveClientMixin
    implements DownloadsOptionsTab {
  static const _sidePadding = 8.0;

  final Map<String, FocusNode> _nodes = {};
  FocusNode? _firstCard;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// This tab has no options; the screen's mobile options action is hidden for it.
  @override
  void showOptionsSheet() {}

  @override
  void focusTopContent() {
    final first = _firstCard;
    if (first != null && first.canRequestFocus) first.requestFocus();
  }

  FocusNode _nodeFor(MediaItem item) => _nodes.putIfAbsent(item.globalKey, () => FocusNode(debugLabel: item.globalKey));

  void _forgetNodesOutside(Set<String> keys) {
    final stale = _nodes.keys.where((key) => !keys.contains(key)).toList();
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final key in stale) {
        _nodes.remove(key)?.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.isActive) return const SizedBox.shrink();
    return Consumer<DownloadProvider>(
      builder: (context, provider, _) {
        final channels = groupReplayDownloadsByChannel([
          ...provider.downloadedShows.where((item) => item.backend.isReplay),
          ...provider.downloadedMovies.where((item) => item.backend.isReplay),
        ]);
        _forgetNodesOutside({
          for (final channel in channels)
            for (final item in channel.items) item.globalKey,
        });
        if (channels.isEmpty) return _emptyState();
        return _sections(channels);
      },
    );
  }

  Widget _emptyState() {
    return EmptyStateWidget(
      message: t.downloads.noDownloads,
      subtitle: t.downloads.noDownloadsDescription,
      icon: Symbols.download_rounded,
      iconSize: 80,
    );
  }

  Widget _sections(List<ReplayDownloadChannel> channels) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxWidth - _sidePadding * 2;
        final columns = math.max(
          1,
          ((usable + ReplayDownloadsTab.gap) / (ReplayDownloadsTab.cardSize.width + ReplayDownloadsTab.gap)).floor(),
        );
        final grids = [
          for (final channel in channels) [for (final item in channel.items) _nodeFor(item)],
        ];
        _firstCard = grids.first.first;
        return SingleChildScrollView(
          key: const PageStorageKey('downloads_grid_catch_up'),
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(_sidePadding, 28, _sidePadding, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var g = 0; g < channels.length; g++) ...[
                if (g > 0) const SizedBox(height: 32),
                ReplayDownloadChannelHeader(channel: channels[g]),
                const SizedBox(height: 12),
                _grid(channels[g], grids, g, columns),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _grid(ReplayDownloadChannel channel, List<List<FocusNode>> grids, int g, int columns) {
    final nodes = grids[g];
    return Wrap(
      spacing: ReplayDownloadsTab.gap,
      runSpacing: ReplayDownloadsTab.gap,
      children: [
        for (var i = 0; i < channel.items.length; i++)
          SizedBox.fromSize(
            size: ReplayDownloadsTab.cardSize,
            child: FocusableMediaCard(
              item: channel.items[i],
              focusNode: nodes[i],
              viewModeOverride: ViewMode.grid,
              cardShapeOverride: CardShape.wide,
              fullBleedImage: true,
              isOffline: true,
              onBack: widget.onBack,
              onNavigateLeft: () => _left(nodes, i, columns),
              onNavigateRight: () => _right(nodes, i, columns),
              onNavigateUp: () => _up(grids, g, i, columns),
              onNavigateDown: () => _down(grids, g, i, columns),
            ),
          ),
      ],
    );
  }

  void _left(List<FocusNode> nodes, int i, int columns) {
    if (i % columns == 0) {
      MainScreenFocusScope.focusSidebarOf(context);
    } else {
      nodes[i - 1].requestFocus();
    }
  }

  void _right(List<FocusNode> nodes, int i, int columns) {
    if (i % columns != columns - 1 && i + 1 < nodes.length) nodes[i + 1].requestFocus();
  }

  void _up(List<List<FocusNode>> grids, int g, int i, int columns) {
    if (i >= columns) {
      grids[g][i - columns].requestFocus();
    } else if (g == 0) {
      widget.onBack?.call();
    } else {
      final previous = grids[g - 1];
      final lastRowStart = ((previous.length - 1) ~/ columns) * columns;
      previous[math.min(lastRowStart + i % columns, previous.length - 1)].requestFocus();
    }
  }

  void _down(List<List<FocusNode>> grids, int g, int i, int columns) {
    final nodes = grids[g];
    final lastRow = (nodes.length - 1) ~/ columns;
    if (i ~/ columns < lastRow) {
      nodes[math.min(i + columns, nodes.length - 1)].requestFocus();
    } else if (g + 1 < grids.length) {
      grids[g + 1][math.min(i % columns, grids[g + 1].length - 1)].requestFocus();
    }
  }
}

/// A broadcaster's logo tile, name and number of programmes: 32 high, never focusable.
class ReplayDownloadChannelHeader extends StatelessWidget {
  final ReplayDownloadChannel channel;

  const ReplayDownloadChannelHeader({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = channel.items.length;
    return Semantics(
      header: true,
      child: SizedBox(
        height: ReplayDownloadsTab.headerHeight,
        child: Row(
          children: [
            ReplayChannelLogo.tile(sourceId: channel.sourceId, name: channel.name, color: scheme.onSurface),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              count == 1 ? t.replay.downloads.programmeOne : t.replay.downloads.programmeMany(count: count),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
