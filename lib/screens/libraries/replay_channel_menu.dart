import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/input_mode_tracker.dart';
import '../../focus/key_event_utils.dart';
import '../../media/media_library.dart';
import '../../utils/focus_utils.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/clickable_cursor.dart';
import '../../widgets/replay_channel_logo.dart';

/// Opens the list of channels under [anchorRect] and returns the global key of the channel picked, or null when the
/// list was dismissed. Focus starts on the channel being browsed.
Future<String?> showReplayChannelMenu(
  BuildContext context, {
  required Rect anchorRect,
  required List<MediaLibrary> channels,
  required String selectedKey,
}) {
  return showAnchoredPanel<String>(
    context,
    anchorRect: anchorRect,
    width: ReplayChannelMenuList.width,
    builder: (_) => ReplayChannelMenuList(channels: channels, selectedKey: selectedKey),
  );
}

/// The rows of the channel menu: logo tile, name, and a check mark on the channel being browsed.
class ReplayChannelMenuList extends StatefulWidget {
  static const width = 300.0;
  static const padding = 8.0;

  final List<MediaLibrary> channels;
  final String selectedKey;

  const ReplayChannelMenuList({super.key, required this.channels, required this.selectedKey});

  @override
  State<ReplayChannelMenuList> createState() => _ReplayChannelMenuListState();
}

class _ReplayChannelMenuListState extends State<ReplayChannelMenuList> {
  final _initialFocus = FocusNode(debugLabel: 'ReplayChannelMenuInitial');

  @override
  void initState() {
    super.initState();
    FocusUtils.requestFocusAfterBuild(this, _initialFocus);
  }

  @override
  void dispose() {
    _initialFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected = widget.channels.any((c) => c.globalKey == widget.selectedKey);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(ReplayChannelMenuList.padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.channels.length; i++)
            _ChannelRow(
              channel: widget.channels[i],
              selected: widget.channels[i].globalKey == widget.selectedKey,
              focusNode: (hasSelected ? widget.channels[i].globalKey == widget.selectedKey : i == 0)
                  ? _initialFocus
                  : null,
            ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatefulWidget {
  static const height = 52.0;

  final MediaLibrary channel;
  final bool selected;
  final FocusNode? focusNode;

  const _ChannelRow({required this.channel, required this.selected, this.focusNode});

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  FocusNode? _ownedNode;
  bool _focused = false;
  bool _hovered = false;

  FocusNode get _node => widget.focusNode ?? (_ownedNode ??= FocusNode(debugLabel: 'ReplayChannelRow'));

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_ChannelRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedNode)?.removeListener(_onFocusChange);
      _node.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    _ownedNode?.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = _node.hasFocus;
    if (focused == _focused) return;
    setState(() => _focused = focused);
    if (focused) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 100));
  }

  void _choose() => Navigator.pop(context, widget.channel.globalKey);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showFocus = _focused && InputModeTracker.isKeyboardMode(context);
    final Color fill = showFocus
        ? scheme.primary
        : _hovered
        ? scheme.onSurface.withValues(alpha: 0.08)
        : Colors.transparent;
    final ink = showFocus ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: Focus(
        focusNode: _node,
        onKeyEvent: (node, event) {
          if (SelectKeyUpSuppressor.consumeIfSuppressed(event)) return KeyEventResult.handled;
          return dpadKeyHandler(onSelect: _choose, trapHorizontalEdges: true)(node, event);
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: ClickableCursor(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _choose,
              child: Container(
                height: _ChannelRow.height,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    ReplayChannelLogo.tile(sourceId: widget.channel.id, name: widget.channel.title, color: ink),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.channel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (widget.selected) AppIcon(Symbols.check_rounded, size: 22, color: ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
