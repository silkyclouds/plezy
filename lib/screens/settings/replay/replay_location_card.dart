import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_regions.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_menu.dart';
import '../../../widgets/focusable_list_tile.dart';

/// Where the app thinks the viewer is, and a way to correct it. Catch-up rights follow the viewer's country, so the
/// rest of the screen is judged against this.
class ReplayLocationCard extends StatelessWidget {
  final String? country;
  final bool overridden;
  final String locale;

  /// Called with a country code, or null to go back to automatic detection.
  final ValueChanged<String?> onChanged;

  const ReplayLocationCard({
    super.key,
    required this.country,
    required this.overridden,
    required this.locale,
    required this.onChanged,
  });

  String _summary() {
    if (country == null) return t.replay.location.unknown;
    final name = replayCountryName(country!, locale);
    return overridden ? t.replay.location.chosen(country: name) : t.replay.location.detected(country: name);
  }

  Future<void> _pick(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final countries = replayKnownCountries()
      ..sort((a, b) => replayCountryName(a, locale).compareTo(replayCountryName(b, locale)));
    const automatic = '';
    final choice = await showAdaptiveAppMenu<String>(
      context,
      title: t.replay.location.pick,
      entries: [
        AppMenuItem<String>(
          value: automatic,
          icon: Symbols.my_location_rounded,
          label: t.replay.location.automatic,
          selected: !overridden,
        ),
        for (final code in countries)
          AppMenuItem<String>(
            value: code,
            label: replayCountryName(code, locale),
            selected: overridden && code == country,
          ),
      ],
      anchorRect: Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height),
      focusFirstItem: true,
    );
    if (choice != null) onChanged(choice.isEmpty ? null : choice);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Builder(
          builder: (tileContext) => FocusableListTile(
            leading: const AppIcon(Symbols.location_on_rounded, fill: 1),
            title: Text(t.replay.location.title),
            subtitle: Text('${_summary()}\n${t.replay.location.hint}'),
            trailing: Text(t.replay.location.change, style: TextStyle(color: scheme.primary)),
            onTap: () => _pick(tileContext),
          ),
        ),
      ),
    );
  }
}
