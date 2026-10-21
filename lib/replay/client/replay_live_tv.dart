import '../../media/live_tv_support.dart';
import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../models/transcode_quality_preset.dart';

/// Live channels are not offered by catch-up sources, so every query is empty.
class ReplayLiveTv implements LiveTvSupport {
  const ReplayLiveTv();

  @override
  LiveTvDvrSupport? get dvr => null;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<LiveTvChannel>> fetchChannels({String? lineup}) async => const [];

  @override
  Future<List<LiveTvProgram>> fetchSchedule({DateTime? from, DateTime? to}) async => const [];

  @override
  Future<LiveTvPlaybackSession?> startPlayback(
    String channelKey, {
    String? dvrKey,
    TranscodeQualityPreset quality = TranscodeQualityPreset.original,
  }) async => null;

  @override
  Future<String> buildFavoriteChannelSource({String? lineup}) async => 'server://replay/none';

  @override
  String get favoriteStoreKey => 'replay';

  @override
  FavoriteChannelPersistenceMode get favoritePersistenceMode => FavoriteChannelPersistenceMode.serverSlice;

  @override
  Future<List<FavoriteChannel>> fetchFavoriteChannels({bool migrate = true, void Function()? checkCurrent}) async =>
      const [];

  @override
  Future<void> setFavoriteChannels(List<FavoriteChannel> channels, {void Function()? checkCurrent}) async {}
}
