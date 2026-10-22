import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'app_logger.dart';
import 'logo_knockout.dart';
import 'single_frame_codec.dart';

/// Cache key for [KnockoutLogoImage]: the wrapped provider's key, so the cleaned copy has its own [ImageCache] entry.
@immutable
class KnockoutLogoKey {
  const KnockoutLogoKey._(this._providerCacheKey);

  final Object _providerCacheKey;

  @override
  bool operator ==(Object other) => other is KnockoutLogoKey && other._providerCacheKey == _providerCacheKey;

  @override
  int get hashCode => Object.hash('knockout', _providerCacheKey);
}

/// Shows a logo published as an opaque picture on white as a mark on a transparent background (see
/// [knockOutWhiteBackground]). Pictures that are not such logos decode unchanged, so it is safe to wrap any logo.
@immutable
class KnockoutLogoImage extends ImageProvider<KnockoutLogoKey> {
  const KnockoutLogoImage(this.imageProvider);

  final ImageProvider imageProvider;

  /// Frames larger than this decode unchanged: logos are bounded well below it.
  static const int _maxPixels = 1 << 21;

  @override
  Future<KnockoutLogoKey> obtainKey(ImageConfiguration configuration) {
    Completer<KnockoutLogoKey>? completer;
    SynchronousFuture<KnockoutLogoKey>? result;
    imageProvider.obtainKey(configuration).then((Object key) {
      final wrapped = KnockoutLogoKey._(key);
      if (completer == null) {
        result = SynchronousFuture<KnockoutLogoKey>(wrapped);
      } else {
        completer.complete(wrapped);
      }
    });
    if (result != null) return result!;
    completer = Completer<KnockoutLogoKey>();
    return completer.future;
  }

  @override
  ImageStreamCompleter loadImage(KnockoutLogoKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> decodeCleaned(ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) async {
      final codec = await decode(buffer, getTargetSize: getTargetSize);
      if (codec.frameCount != 1) return codec;
      return _clean(codec);
    }

    return imageProvider.loadImage(key._providerCacheKey, decodeCleaned);
  }

  Future<ui.Codec> _clean(ui.Codec codec) async {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      ui.Image? cleaned;
      try {
        cleaned = await _knockOut(image);
      } catch (error, stackTrace) {
        // Best effort: the original picture is what would show without this step.
        appLogger.w('Logo background removal failed', error: error, stackTrace: stackTrace);
      }
      final result = cleaned ?? image.clone();
      codec.dispose();
      return SingleFrameCodec(result);
    } finally {
      image.dispose();
    }
  }

  Future<ui.Image?> _knockOut(ui.Image image) async {
    if (image.width * image.height > _maxPixels) return null;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return null;
    final cleaned = knockOutWhiteBackground(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), image.width, image.height);
    if (cleaned == null) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(cleaned);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      rowBytes: image.width * 4,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  @override
  bool operator ==(Object other) => other is KnockoutLogoImage && other.imageProvider == imageProvider;

  @override
  int get hashCode => Object.hash('knockout', imageProvider);
}
