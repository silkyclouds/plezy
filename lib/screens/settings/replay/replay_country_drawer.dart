import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/key_event_utils.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_regions.dart';
import '../../../replay/provider/replay_source_groups.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../widgets/app_icon.dart';
import 'replay_country_phrases.dart';
import 'replay_palette.dart';
import 'replay_reveal.dart';
import 'replay_row.dart';

/// Puts the channels of a country's group in the order the screen shows them: the language of the interface first.
List<ReplayLanguageGroup> orderedLanguageGroups(ReplayCountryGroup group, String locale) {
  final languages = [...group.languages];
  final first = languages.indexWhere((language) => language.language == locale);
  if (first > 0) languages.insert(0, languages.removeAt(first));
  return languages;
}

/// One country of the channel list: a 64 px header that opens and closes, and inside it a switch for the whole
/// country and the channels, split by language when the country has several.
class ReplayCountryDrawer extends StatefulWidget {
  /// The channels to draw; when searching, only those found.
  final ReplayCountryGroup group;

  /// How many of the country's channels exist, how many are on, and how many do not play from the viewer's country.
  final int total;
  final int enabledCount;
  final int blockedCount;
  final String locale;
  final String? viewerCountry;
  final bool expanded;

  /// Open for good, as while searching: the header no longer toggles.
  final bool pinnedOpen;
  final bool autofocusHeader;
  final VoidCallback onToggle;
  final ValueChanged<bool> onToggleAll;
  final Widget Function(ReplaySourceInfo source) channelBuilder;

  const ReplayCountryDrawer({
    super.key,
    required this.group,
    required this.total,
    required this.enabledCount,
    required this.blockedCount,
    required this.locale,
    required this.viewerCountry,
    required this.expanded,
    required this.pinnedOpen,
    required this.autofocusHeader,
    required this.onToggle,
    required this.onToggleAll,
    required this.channelBuilder,
  });

  @override
  State<ReplayCountryDrawer> createState() => _ReplayCountryDrawerState();
}

class _ReplayCountryDrawerState extends State<ReplayCountryDrawer> {
  final _header = FocusNode(debugLabel: 'ReplayCountryHeader');
  final _headerKey = GlobalKey();

  bool get _open => widget.expanded || widget.pinnedOpen;

  @override
  void dispose() {
    _header.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.pinnedOpen) return;
    widget.onToggle();
    if (!widget.expanded && _headerKey.currentContext != null) revealBelowTitleBar(_headerKey.currentContext!);
  }

  KeyEventResult _bodyKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey.isBackKey) return handleBackKeyAction(event, _header.requestFocus);
    if (event.isActionable && event.logicalKey.isLeftKey) {
      _header.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _counter() {
    final blocked = widget.blockedCount;
    if (blocked == 0 || widget.viewerCountry == null) {
      return t.replay.setup.enabledCount(enabled: widget.enabledCount, total: widget.total);
    }
    final from = replayCountryFrom(widget.viewerCountry!, widget.locale);
    if (blocked == 1) {
      return t.replay.setup.enabledCountWarnedOne(enabled: widget.enabledCount, total: widget.total, country: from);
    }
    return t.replay.setup.enabledCountWarned(
      enabled: widget.enabledCount,
      total: widget.total,
      blocked: blocked,
      country: from,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final code = widget.group.country;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: palette.group, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: _headerKey,
            child: ReplayRow(
              focusNode: _header,
              autofocus: widget.autofocusHeader,
              minHeight: 64,
              lead: code == replayInternational
                  ? const AppIcon(Symbols.public_rounded, size: 24)
                  : Text(code, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              title: replayCountryName(code, widget.locale),
              titleWeight: FontWeight.w600,
              details: [Text(_counter())],
              trailing: AppIcon(_open ? Symbols.expand_less_rounded : Symbols.expand_more_rounded, size: 28),
              onSelect: _toggle,
              onRight: !_open ? _toggle : null,
              onLeft: widget.expanded && !widget.pinnedOpen ? _toggle : null,
            ),
          ),
          if (_open) Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _bodyKey, child: _body(palette)),
        ],
      ),
    );
  }

  Widget _body(ReplayPalette palette) {
    final all = widget.enabledCount == widget.total;
    final languages = orderedLanguageGroups(widget.group, widget.locale);
    final labelled = widget.group.languages.length > 1 && !widget.pinnedOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.pinnedOpen)
          ReplayRow(
            minHeight: 64,
            lead: const AppIcon(Symbols.select_all_rounded, size: 26),
            title: widget.group.country == replayInternational
                ? t.replay.setup.allInternational
                : t.replay.setup.allChannels(country: replayCountryOf(widget.group.country, widget.locale)),
            trailing: ReplayRow.switchOf(all),
            onSelect: () => widget.onToggleAll(!all),
          ),
        for (final language in languages) ...[
          if (labelled)
            Container(
              height: 40,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: ReplayRow.textInset),
              child: Text(
                replayLanguageName(language.language, widget.locale),
                style: TextStyle(color: palette.muted, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          for (final source in language.sources) widget.channelBuilder(source),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
