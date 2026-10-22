import 'dart:async';

import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'urplay_api.dart';
import 'urplay_catalog.dart';
import 'urplay_playback.dart';
import 'urplay_refs.dart';

/// Tells which titles UR keeps to viewers in Sweden.
///
/// The catalogue carries no such flag, but the stream endpoint answers a refusal that names the reason, and the
/// refusal is cheap. Each programme is asked once and the answer is kept for hours; a show or season is judged by
/// its first programme, since UR restricts whole acquired series at once.
class UrAvailabilityProbe {
  static const _defaultBudget = Duration(milliseconds: 4500);
  static const _answerTtl = Duration(hours: 6);
  static const _workers = 6;
  static const _maxTitles = 48;

  final UrPlayApi _api;
  final UrCatalog _catalog;
  final Duration _budget;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, bool swedenOnly})> _answers = {};

  UrAvailabilityProbe(this._api, this._catalog, {Duration? budget, DateTime Function()? now})
    : _budget = budget ?? _defaultBudget,
      _now = now ?? DateTime.now;

  /// Verdicts for the titles answered within the time budget; the rest are left out and answered by a later call,
  /// because every probe that finishes is kept.
  Future<Map<ReplayRef, ReplayAvailability>> predict(List<ReplayTitle> titles, String country) async {
    if (country.toUpperCase() == 'SE') return const {};
    final verdicts = <ReplayRef, ReplayAvailability>{};
    var open = true;
    final queue = titles.where((t) => t.availability == ReplayAvailability.playable).take(_maxTitles).iterator;

    Future<void> worker() async {
      while (open && queue.moveNext()) {
        final title = queue.current;
        final swedenOnly = await _swedenOnly(title);
        if (swedenOnly != null && open) {
          verdicts[title.ref] = swedenOnly ? ReplayAvailability.geoBlocked : ReplayAvailability.playable;
        }
      }
    }

    try {
      await Future.wait([for (var i = 0; i < _workers; i++) worker()]).timeout(_budget);
    } on TimeoutException {
      // Late answers stay in the cache for the next call.
    } finally {
      open = false;
    }
    return Map.of(verdicts);
  }

  Future<bool?> _swedenOnly(ReplayTitle title) async {
    try {
      final programId = await _programId(title);
      return programId == null ? null : await _ask(programId);
    } on MediaServerHttpException {
      return null;
    } on UrPlayRateLimitedException {
      return null;
    }
  }

  Future<String?> _programId(ReplayTitle title) async {
    final target = UrTarget.parse(title.ref);
    return switch (target) {
      UrProgram(:final programId) => programId,
      UrShow(:final seriesId) => _catalog.firstProgramId(seriesId),
      UrSeason(:final seriesId) => _catalog.firstProgramId(seriesId),
      null => null,
    };
  }

  Future<bool?> _ask(String programId) async {
    final known = _answers[programId];
    if (known != null && _now().difference(known.at) < _answerTtl) return known.swedenOnly;
    final reply = await _api.sources(programId);
    final bool swedenOnly;
    if (reply.statusCode == 200) {
      swedenOnly = false;
    } else if (reply.statusCode == 403 && reply.message == urSwedenOnlyMessage) {
      swedenOnly = true;
    } else {
      return null;
    }
    _answers[programId] = (at: _now(), swedenOnly: swedenOnly);
    return swedenOnly;
  }
}
