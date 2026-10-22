import 'dart:async';

import '../../utils/app_logger.dart';
import '../model/replay_ref.dart';
import '../model/replay_title.dart';
import '../provider/replay_provider.dart';

/// Asks a broadcaster, before a list is shown, which of its titles the viewer's country cannot watch.
///
/// Only providers that implement [ReplayAvailabilityPredictor] are asked. A slow or failing answer leaves every title
/// as it was: a missing forecast must never hide or grey out content on a guess.
class ReplayForecast {
  static const _timeout = Duration(seconds: 6);

  final String? Function() viewerCountry;

  const ReplayForecast(this.viewerCountry);

  /// Verdicts other than "playable" for [titles], keyed by title.
  Future<Map<ReplayRef, ReplayAvailability>> predict(ReplayProvider provider, Iterable<ReplayTitle> titles) async {
    final country = viewerCountry();
    if (provider is! ReplayAvailabilityPredictor || country == null) return const {};
    final predictor = provider as ReplayAvailabilityPredictor;
    final asked = titles.toList(growable: false);
    if (asked.isEmpty) return const {};
    try {
      final verdicts = await predictor.predictAvailability(asked, country).timeout(_timeout);
      return {
        for (final entry in verdicts.entries)
          if (entry.value != ReplayAvailability.playable) entry.key: entry.value,
      };
    } on TimeoutException {
      appLogger.w('Availability forecast from ${provider.source.name} took too long');
    } on Exception catch (error) {
      appLogger.w('Availability forecast from ${provider.source.name} failed', error: error);
    }
    return const {};
  }
}
