import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../connection/connection.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../profile/profile_switch_screen.dart';
import 'connection_persistence.dart';

/// Creates the built-in catch-up TV connection and binds it to a profile, with [sources] enabled
/// (every broadcaster when null). Returns false when no profile could be chosen.
Future<bool> addReplayConnection(BuildContext context, {Set<String>? sources, Profile? targetProfile}) async {
  final active = context.read<ActiveProfileProvider>();
  await active.initialize();
  if (!context.mounted) return false;
  final profile = await _profileToBind(context, active, targetProfile);
  if (profile == null || !context.mounted) return false;

  final now = DateTime.now();
  final connection = ReplayConnection(
    enabledSources: [
      for (final id in replaySourceIds)
        if (sources == null || sources.contains(id)) id,
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
  if (!context.mounted) return false;
  if (!profile.isNew && profile.profile.id == active.activeId) {
    await context.read<ActiveProfileBinder>().rebindIfActive(profile.profile.id);
  }
  return true;
}

/// The profile that receives the connection: the target, the active one, a pick from the existing
/// profiles, or a new local profile on first run.
Future<({Profile profile, bool isNew})?> _profileToBind(
  BuildContext context,
  ActiveProfileProvider active,
  Profile? targetProfile,
) async {
  final target = targetProfile ?? active.active;
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
