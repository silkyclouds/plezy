import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_regions.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_menu.dart';
import 'replay_country_phrases.dart';
import 'replay_menu.dart';
import 'replay_palette.dart';
import 'replay_pill.dart';
import 'replay_row.dart';

/// Where the app thinks the viewer is, and a way to correct it. Catch-up rights follow the viewer's country, so the
/// rest of the screen is judged against this.
class ReplayLocationCard extends StatefulWidget {
  /// The country in use: the viewer's choice when [overridden], else the detected one.
  final String? country;
  final bool overridden;

  /// The country found from the connection, shown when the viewer chose another.
  final String? detected;

  /// Countries that have channels, in the order the menu lists them.
  final List<String> countries;
  final String locale;

  /// Opens the menu as soon as the card is shown.
  final bool openMenuOnShow;

  /// Called with a country code, or null to go back to automatic detection.
  final ValueChanged<String?> onChanged;

  const ReplayLocationCard({
    super.key,
    required this.country,
    required this.overridden,
    required this.detected,
    required this.countries,
    required this.locale,
    required this.onChanged,
    this.openMenuOnShow = false,
  });

  @override
  State<ReplayLocationCard> createState() => _ReplayLocationCardState();
}

class _ReplayLocationCardState extends State<ReplayLocationCard> {
  final _button = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.openMenuOnShow) WidgetsBinding.instance.addPostFrameCallback((_) => _openMenu());
  }

  String _name(String code) => replayCountryName(code, widget.locale);

  String get _title => widget.country == null
      ? t.replay.location.titleUnknown
      : t.replay.location.title(country: _name(widget.country!));

  String get _hint {
    final country = widget.country;
    if (country == null) return t.replay.location.unknown;
    if (!widget.overridden) {
      return t.replay.location.detected(country: replayCountryFrom(country, widget.locale));
    }
    final detected = widget.detected;
    return detected == null ? t.replay.location.chosenOnly : t.replay.location.chosen(country: _name(detected));
  }

  Future<void> _openMenu() async {
    final context = _button.currentContext;
    if (context == null || !context.mounted) return;
    final detected = widget.detected;
    final automatic = detected == null
        ? t.replay.location.automaticUnknown
        : t.replay.location.automatic(country: _name(detected));
    final choice = await showReplayMenu<String>(
      context,
      anchor: replayAnchorRect(context),
      alignment: AppMenuAnchorAlignment.end,
      entries: [
        ReplayMenuEntry(value: '', label: automatic, selected: !widget.overridden),
        for (final code in widget.countries)
          ReplayMenuEntry(value: code, label: _name(code), selected: widget.overridden && code == widget.country),
      ],
    );
    if (choice != null) widget.onChanged(choice.isEmpty ? null : choice);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.fromLTRB(ReplayRow.groupInset + 2 + 18, 12, ReplayRow.groupInset + 2 + 8, 12),
      decoration: BoxDecoration(color: palette.group, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const SizedBox(
            width: ReplayRow.leadWidth,
            child: Center(child: AppIcon(Symbols.location_on_rounded, size: 26)),
          ),
          const SizedBox(width: ReplayRow.leadGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_hint, style: TextStyle(fontSize: 15, color: palette.muted, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          KeyedSubtree(
            key: _button,
            child: ReplayPill(label: t.replay.location.change, onPressed: _openMenu),
          ),
        ],
      ),
    );
  }
}
