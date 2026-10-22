import '../../model/replay_ref.dart';

/// Who the catalogue lets watch an item: the two flags DR puts on every card.
class DrtvAccess {
  /// Only viewers in Denmark can stream it.
  final bool denmarkOnly;

  /// Only a DRM-protected stream exists, which this app does not play.
  final bool drm;

  const DrtvAccess({this.denmarkOnly = false, this.drm = false});
}

/// Reads the access flags of a catalogue item. The flags are the strings "True" and "False", not booleans.
///
/// A flag the item does not carry comes from [inherited], the show or season it belongs to: episodes name no DRM flag.
DrtvAccess drtvAccessOf(Map<String, dynamic> item, {DrtvAccess? inherited}) {
  final fields = item['customFields'];
  final custom = fields is Map<String, dynamic> ? fields : const <String, dynamic>{};
  final geo = custom['IsGeoRestricted'];
  final drmKeys = custom.keys.where((k) => k.endsWith('DRMPlayoutRequired'));
  final drm = drmKeys.isEmpty ? null : drmKeys.any((k) => _isTrue(custom[k]));
  return DrtvAccess(
    denmarkOnly: geo == null ? (inherited?.denmarkOnly ?? false) : _isTrue(geo),
    drm: drm ?? inherited?.drm ?? false,
  );
}

bool _isTrue(Object? flag) => flag == true || (flag is String && flag.toLowerCase() == 'true');

/// What was last seen of each title's flags, so a list can be judged for a viewer's country without another request.
class DrtvAccessBook {
  final Map<ReplayRef, DrtvAccess> _byRef = {};

  void record(ReplayRef ref, DrtvAccess access) => _byRef[ref] = access;

  DrtvAccess? of(ReplayRef ref) => _byRef[ref];
}
