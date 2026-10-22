import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../replay/client/replay_client.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../replay/provider/replay_regions.dart';
import '../../replay/provider/replay_source_groups.dart';
import '../../replay/provider/replay_source_info.dart';
import '../../replay/suggestions/replay_suggestion_events.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import 'replay/replay_channel_list.dart';
import 'replay/replay_initial_sources.dart';
import 'replay/replay_location_card.dart';
import 'replay/replay_menu.dart';
import 'replay/replay_sign_in_dialog.dart';
import 'replay/replay_suggestions_entry.dart';
import 'replay/replay_suggestions_launcher.dart';
import 'replay/replay_text_field.dart';
import 'replay_connection_setup.dart';

/// Chooses which broadcasters catch-up TV shows, country by country, and signs the viewer in to the ones that have
/// accounts. The viewer's country decides which channels carry a warning.
class ReplaySettingsScreen extends StatefulWidget {
  /// Opens the location menu as soon as the screen is shown, for a "change location" shortcut.
  final bool openLocationMenu;

  const ReplaySettingsScreen({super.key, this.openLocationMenu = false});

  @override
  State<ReplaySettingsScreen> createState() => _ReplaySettingsScreenState();
}

class _ReplaySettingsScreenState extends State<ReplaySettingsScreen> {
  static const _locationWait = Duration(seconds: 3);

  ReplayConnection? _connection;
  bool _loaded = false;
  String? _country;
  String? _detected;
  bool _overridden = false;
  String? _expanded;
  String _query = '';
  final _search = TextEditingController();
  Future<void> _writes = Future.value();

  String get _locale => LocaleSettings.currentLocale.languageCode;

  ReplayClient? get _client => replayClientOf(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Loads the connection; the first visit creates it with the channels that suit the viewer's country, so there is
  /// no separate "add" step between the settings entry and the channel list.
  Future<void> _load() async {
    final registry = context.read<ConnectionRegistry>();
    var connection = await registry.get(ReplayConnection.singletonId);
    if (!mounted) return;
    if (connection is! ReplayConnection) {
      final sources = await detectInitialReplaySources();
      if (!mounted) return;
      if (await addReplayConnection(context, sources: sources) && mounted) {
        connection = await registry.get(ReplayConnection.singletonId);
      }
      if (!mounted) return;
    }
    _connection = connection is ReplayConnection ? connection : null;
    await _resolveLocation();
    if (!mounted) return;
    setState(() {
      _expanded ??= _groups().firstOrNull?.country;
      _loaded = true;
    });
  }

  /// Waits briefly for the country, so the right drawer is open on the first frame; a slower lookup updates the
  /// screen when it lands.
  Future<void> _resolveLocation() async {
    final geo = _client?.geo;
    if (geo == null) return;
    final lookup = geo.resolve();
    try {
      await lookup.timeout(_locationWait);
    } on TimeoutException {
      unawaited(lookup.then((_) => _applyLocation()));
    }
    _applyLocation();
  }

  void _applyLocation() {
    final geo = _client?.geo;
    if (!mounted || geo == null) return;
    setState(() {
      _country = geo.country;
      _detected = geo.detected;
      _overridden = geo.override != null;
      _expanded ??= _groups().firstOrNull?.country;
    });
  }

  List<ReplayCountryGroup> _groups() => groupReplaySources(replaySourceInfos, viewerCountry: _country, locale: _locale);

  Future<void> _changeLocation(String? code) async {
    await _client?.geo?.setOverride(code);
    _applyLocation();
    notifyReplaySuggestionsChanged();
  }

  List<String> _countriesWithChannels() {
    final codes = {for (final info in replaySourceInfos) info.country}..remove(replayInternational);
    return codes.toList()..sort((a, b) => replayCountryName(a, _locale).compareTo(replayCountryName(b, _locale)));
  }

  /// Applies the change on screen at once and writes it behind earlier writes, so a burst of switches ends with the
  /// last state stored.
  void _setEnabled(Set<String> ids, bool on) {
    final current = _connection;
    if (current == null) return;
    final sources = {...current.enabledSources};
    on ? sources.addAll(ids) : sources.removeAll(ids);
    final updated = current.copyWith(
      enabledSources: [
        for (final id in replaySourceIds)
          if (sources.contains(id)) id,
      ],
    );
    setState(() => _connection = updated);
    final registry = context.read<ConnectionRegistry>();
    final binder = context.read<ActiveProfileBinder>();
    final activeId = context.read<ActiveProfileProvider>().activeId;
    _writes = _writes.then((_) async {
      await registry.upsert(updated);
      if (activeId != null) await binder.rebindIfActive(activeId);
      notifyReplaySuggestionsChanged();
    });
  }

  Future<void> _openAccount(ReplaySourceInfo info, BuildContext rowContext) async {
    final accounts = _client?.accounts;
    if (accounts == null) return;
    if (accounts.accountLabel(info.id) != null) {
      final out = await showReplayMenu<bool>(
        rowContext,
        anchor: replayAnchorRect(rowContext),
        alignment: AppMenuAnchorAlignment.end,
        entries: [ReplayMenuEntry(value: true, label: t.replay.signOut, icon: Symbols.logout_rounded)],
      );
      if (out == true) await accounts.signOut(info.id);
    } else {
      await showReplaySignIn(context, accounts: accounts, info: info);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final connection = _connection;
    return FocusedScrollScaffold(
      title: Text(t.replay.title),
      slivers: [
        SliverToBoxAdapter(
          child: !_loaded
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : connection == null
              ? _notAdded()
              : _content(connection),
        ),
      ],
    );
  }

  Widget _notAdded() => Padding(
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
    if (await addReplayConnection(context) && mounted) {
      setState(() => _loaded = false);
      await _load();
    }
  }

  Widget _content(ReplayConnection connection) {
    final client = _client;
    final accounts = client?.accounts;
    final enabled = connection.enabledSources.toSet();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReplayLocationCard(
            country: _country,
            overridden: _overridden,
            detected: _detected,
            countries: _countriesWithChannels(),
            locale: _locale,
            openMenuOnShow: widget.openLocationMenu,
            onChanged: (code) => unawaited(_changeLocation(code)),
          ),
          if (client != null) ...[
            const SizedBox(height: 16),
            ReplaySuggestionsEntry(
              store: client.suggestionSettings,
              automaticLanguages: client.automaticSuggestionLanguages,
              enabledChannels: [for (final id in connection.enabledSources) ?replaySourceInfo(id)],
              locale: _locale,
              onOpen: () => openReplaySuggestionSettings(context),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ReplayTextField(
              controller: _search,
              prefixIcon: Symbols.search_rounded,
              hint: t.replay.setup.searchHint,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          ReplayChannelList(
            groups: _groups(),
            enabled: enabled,
            query: _query,
            locale: _locale,
            viewerCountry: _country,
            expandedCountry: _expanded,
            hasAccount: (info) => info.supportsAccount && accounts != null,
            isSignedIn: (info) => accounts?.accountLabel(info.id) != null,
            onToggleCountry: (code) => setState(() => _expanded = _expanded == code ? null : code),
            onSetEnabled: _setEnabled,
            onAccount: (info, rowContext) => unawaited(_openAccount(info, rowContext)),
          ),
        ],
      ),
    );
  }
}
