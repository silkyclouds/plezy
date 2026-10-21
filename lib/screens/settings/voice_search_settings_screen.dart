import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings_service.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_section.dart';

/// Where voice search sends recordings and how it asks for them to be read.
class VoiceSearchSettingsScreen extends StatelessWidget {
  const VoiceSearchSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: Text(t.voiceSearch.title),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            SettingsGroup(
              children: [
                SettingTextTile(
                  pref: SettingsService.voiceSearchUrl,
                  icon: Symbols.mic_rounded,
                  title: t.voiceSearch.url,
                  subtitle: t.voiceSearch.urlDescription,
                  emptyLabel: t.voiceSearch.notSet,
                  hintText: t.voiceSearch.urlHint,
                ),
                SettingTextTile(
                  pref: SettingsService.voiceSearchModel,
                  icon: Symbols.neurology_rounded,
                  title: t.voiceSearch.model,
                  subtitle: t.voiceSearch.modelDescription,
                  emptyLabel: t.voiceSearch.notSet,
                ),
                SettingTextTile(
                  pref: SettingsService.voiceSearchLanguage,
                  icon: Symbols.translate_rounded,
                  title: t.voiceSearch.language,
                  subtitle: t.voiceSearch.languageDescription,
                  emptyLabel: t.voiceSearch.notSet,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }
}
