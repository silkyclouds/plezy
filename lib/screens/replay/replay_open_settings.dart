import 'package:flutter/material.dart';

import '../settings/replay_settings_screen.dart';

/// Opens the catch-up TV settings with the position menu already open, so the viewer can correct the position the
/// app assumes.
Future<void> openReplayLocationSettings(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const ReplaySettingsScreen(openLocationMenu: true)));
