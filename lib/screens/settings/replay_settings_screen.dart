import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../replay/client/replay_client.dart';
import '../../replay/provider/replay_provider.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../replay/provider/replay_source_info.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/settings_section.dart';
import '../../replay/provider/replay_regions.dart';
import '../../replay/provider/replay_source_groups.dart';
import '../../widgets/replay_channel_logo.dart';
import 'replay/replay_country_drawer.dart';
import 'replay/replay_location_card.dart';
import 'replay/replay_sign_in_dialog.dart';
import 'replay_connection_setup.dart';

/// Chooses which broadcasters catch-up TV shows and signs the user in to the ones that have accounts.
class ReplaySettingsScreen extends StatefulWidget {
  const ReplaySettingsScreen({super.key});

  @override
  State<ReplaySettingsScreen> createState() => _ReplaySettingsScreenState();
}

class _ReplaySettingsScreenState extends State<ReplaySettingsScreen> {
  ReplayConnection? _connection;
  bool _loaded = false;
  String? _country;
  bool _countryOverridden = false;
  final Set<String> _expanded = {};
  bool _expansionSeeded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(createIfMissing: true));
  }

  /// Loads the connection; the first visit creates it with every broadcaster enabled, so there is
  /// no separate "add" step between the settings entry and the broadcaster list.
  Future<void> _load({bool createIfMissing = false}) async {
    var connection = await context.read<ConnectionRegistry>().get(ReplayConnection.singletonId);
    if (!mounted) return;
    if (connection is! ReplayConnection && createIfMissing) {
      if (await addReplayConnection(context) && mounted) {
        connection = await context.read<ConnectionRegistry>().get(ReplayConnection.singletonId);
      }
      if (!mounted) return;
    }
    setState(() {
      _connection = connection is ReplayConnection ? connection : null;
      _loaded = true;
    });
    unawaited(_resolveLocation());
  }

  /// Finds the viewer's country, then opens that country's drawer the first time.
  Future<void> _resolveLocation() async {
    final geo = _client?.geo;
    final country = await geo?.resolve();
    if (!mounted) return;
    setState(() {
      _country = country;
      _countryOverridden = geo?.override != null;
      if (!_expansionSeeded) {
        _expansionSeeded = true;
        final first = groupReplaySources(replaySourceInfos, viewerCountry: country, locale: _locale).firstOrNull;
        if (first != null) _expanded.add(first.country);
      }
    });
  }

  Future<void> _changeLocation(String? code) async {
    final geo = _client?.geo;
    if (geo == null) return;
    await geo.setOverride(code);
    if (!mounted) return;
    setState(() {
      _country = geo.country;
      _countryOverridden = geo.override != null;
    });
  }

  String get _locale => LocaleSettings.currentLocale.languageCode;

  ReplayClient? get _client =>
      context.read<MultiServerProvider>().serverManager.getClient(ServerId(ReplayConnection.singletonId))
          as ReplayClient?;

  Future<void> _setEnabled(ReplaySourceInfo info, bool enabled) async {
    final current = _connection;
    if (current == null) return;
    final sources = {...current.enabledSources};
    enabled ? sources.add(info.id) : sources.remove(info.id);
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.replay.needOne)));
      return;
    }
    final updated = ReplayConnection(
      enabledSources: [
        for (final id in replaySourceIds)
          if (sources.contains(id)) id,
      ],
      createdAt: current.createdAt,
      lastAuthenticatedAt: current.lastAuthenticatedAt,
    );
    await context.read<ConnectionRegistry>().upsert(updated);
    if (!mounted) return;
    final activeId = context.read<ActiveProfileProvider>().activeId;
    if (activeId != null) await context.read<ActiveProfileBinder>().rebindIfActive(activeId);
    if (mounted) await _load();
  }

  Future<void> _openAccount(ReplaySourceInfo info) async {
    final accounts = _client?.accounts;
    if (accounts == null) return;
    if (accounts.accountLabel(info.id) != null) {
      final confirmed = await showScopedDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t.replay.signOutTitle(name: info.name)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.replay.signOut)),
          ],
        ),
      );
      if (confirmed == true) await accounts.signOut(info.id);
    } else {
      await showReplaySignIn(context, accounts: accounts, info: info);
    }
    if (mounted) setState(() {});
  }

  String _supportLabel(ReplayPlaybackSupport support) => switch (support) {
    ReplayPlaybackSupport.clear => t.replay.supportClear,
    ReplayPlaybackSupport.partial => t.replay.supportPartial,
    ReplayPlaybackSupport.browseOnly => t.replay.supportBrowseOnly,
  };

  @override
  Widget build(BuildContext context) {
    final connection = _connection;
    return FocusedScrollScaffold(
      title: Text(t.replay.title),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_loaded && connection == null) _notAdded(context) else if (connection != null) _sources(connection),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }

  Widget _notAdded(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.replay.notAdded),
        const SizedBox(height: 12),
        FocusableButton(
          autofocus: true,
          onPressed: () => unawaited(_openAdd()),
          child: FilledButton(onPressed: () => unawaited(_openAdd()), child: Text(t.replay.add)),
        ),
      ],
    ),
  );

  Future<void> _openAdd() async {
    if (await addReplayConnection(context) && mounted) await _load();
  }

  Widget _sources(ReplayConnection connection) {
    final groups = groupReplaySources(replaySourceInfos, viewerCountry: _country, locale: _locale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReplayLocationCard(
          country: _country,
          overridden: _countryOverridden,
          locale: _locale,
          onChanged: (code) => unawaited(_changeLocation(code)),
        ),
        SettingsSectionHeader(t.replay.sources),
        for (final group in groups)
          ReplayCountryDrawer(
            group: group,
            locale: _locale,
            enabledCount: group.sources.where((info) => connection.enabledSources.contains(info.id)).length,
            expanded: _expanded.contains(group.country),
            onToggle: () => setState(() {
              if (!_expanded.remove(group.country)) _expanded.add(group.country);
            }),
            channelBuilder: (info) => _channel(info, connection),
          ),
      ],
    );
  }

  /// The row of one channel: logo, name, what plays, a warning when the viewer's country is outside its rules, and the
  /// switch; a second row for the account when the channel has them.
  List<Widget> _channel(ReplaySourceInfo info, ReplayConnection connection) {
    final accounts = _client?.accounts;
    final enabled = connection.enabledSources.contains(info.id);
    final restricted = info.restrictsViewerIn(_country);
    final scheme = Theme.of(context).colorScheme;
    final extraLanguages = info.languages.skip(1).map((code) => replayLanguageName(code, _locale)).toList();
    return [
      FocusableListTile(
        leading: SizedBox(
          width: 48,
          child: ReplayChannelLogo(sourceId: info.id, name: info.name, height: 26),
        ),
        title: Text(info.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_supportLabel(info.support)),
            if (extraLanguages.isNotEmpty) Text(t.replay.setup.alsoIn(languages: extraLanguages.join(', '))),
            if (restricted)
              Row(
                children: [
                  AppIcon(Symbols.public_off_rounded, fill: 1, size: 14, color: scheme.tertiary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(t.replay.setup.notFromHere, style: TextStyle(color: scheme.tertiary)),
                  ),
                ],
              ),
          ],
        ),
        trailing: Switch(value: enabled, onChanged: (on) => unawaited(_setEnabled(info, on))),
        onTap: () => unawaited(_setEnabled(info, !enabled)),
      ),
      if (info.supportsAccount && enabled && accounts != null)
        FocusableListTile(
          leading: const SizedBox(width: 48, child: AppIcon(Symbols.account_circle_rounded, fill: 1)),
          title: Text(accounts.accountLabel(info.id) == null ? t.replay.signIn : t.replay.signOut),
          subtitle: accounts.accountLabel(info.id) == null
              ? null
              : Text(t.replay.signedInAs(account: accounts.accountLabel(info.id)!)),
          onTap: () => unawaited(_openAccount(info)),
        ),
    ];
  }
}
