import 'replay_provider.dart';

/// What settings shows about a broadcaster before any provider exists for it.
class ReplaySourceInfo {
  final String id;
  final String name;
  final ReplayPlaybackSupport support;

  /// The broadcaster has accounts and its provider implements `ReplayAccountSupport`.
  final bool supportsAccount;

  const ReplaySourceInfo({required this.id, required this.name, required this.support, this.supportsAccount = false});
}
