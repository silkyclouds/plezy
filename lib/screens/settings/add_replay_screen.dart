import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../connection/connection.dart';
import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../profile/profile_switch_screen.dart';
import 'connection_persistence.dart';

/// Adds the built-in catch-up TV connection to a profile. It has no server and no account, so the
/// only choice is which broadcasters to show.
class AddReplayScreen extends StatefulWidget {
  final Profile? targetProfile;

  const AddReplayScreen({super.key, this.targetProfile});

  @override
  State<AddReplayScreen> createState() => _AddReplayScreenState();
}

class _AddReplayScreenState extends State<AddReplayScreen> {
  late final Set<String> _selected = {...replaySourceIds};
  bool _saving = false;

  Future<void> _add() async {
    final active = context.read<ActiveProfileProvider>();
    await active.initialize();
    if (!mounted) return;
    final profile = await _profileToBind(active);
    if (profile == null || !mounted) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final connection = ReplayConnection(
      enabledSources: [
        for (final id in replaySourceIds)
          if (_selected.contains(id)) id,
      ],
      createdAt: now,
      lastAuthenticatedAt: now,
    );
    await persistAndBindConnection(
      context: context,
      connection: connection,
      bindToProfile: ProfileConnection(
        profileId: profile.profile.id,
        connectionId: connection.id,
        userIdentifier: ReplayConnection.singletonId,
        tokenAcquiredAt: now,
      ),
      firstRunProfile: profile.isNew ? profile.profile : null,
    );
    if (!mounted) return;
    if (!profile.isNew && profile.profile.id == active.activeId) {
      await context.read<ActiveProfileBinder>().rebindIfActive(profile.profile.id);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// The profile that receives the connection: the target, the active one, a pick from the existing
  /// profiles, or a new local profile on first run.
  Future<({Profile profile, bool isNew})?> _profileToBind(ActiveProfileProvider active) async {
    final target = widget.targetProfile ?? active.active;
    if (target != null) return (profile: target, isNew: false);
    if (active.profiles.isEmpty) {
      final now = DateTime.now();
      final created = Profile.local(
        id: 'local-${const Uuid().v4()}',
        displayName: t.addServer.catchUpTvTitle,
        sortOrder: now.millisecondsSinceEpoch,
        createdAt: now,
      );
      return (profile: created, isNew: true);
    }
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen(requireSelection: true)));
    final picked = active.active;
    return picked == null ? null : (profile: picked, isNew: false);
  }

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: Text(t.addServer.catchUpTvTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              FocusableButton(
                autofocus: true,
                onPressed: _saving || _selected.isEmpty ? null : _add,
                child: FilledButton(
                  onPressed: _saving || _selected.isEmpty ? null : _add,
                  child: Text(t.addServer.catchUpTvAdd),
                ),
              ),
              if (_selected.isEmpty) Text(t.addServer.catchUpTvNoSource),
              const SizedBox(height: 16),
              Text(t.addServer.catchUpTvSources, style: Theme.of(context).textTheme.titleMedium),
              for (final id in replaySourceIds)
                CheckboxListTile(
                  value: _selected.contains(id),
                  title: Text(replaySourceName(id)),
                  onChanged: (on) => setState(() => on == true ? _selected.add(id) : _selected.remove(id)),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}
