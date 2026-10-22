import 'dart:ui' as ui;

/// Serves one already-decoded frame, cloning it per pull so every caller owns
/// its copy. Replaces the engine codec after its lazy single frame has been
/// consumed for analysis; the engine's raw-pixel codecs decode lazily from
/// their descriptor, so they cannot outlive the disposal of their buffer the
/// way this wrapper can.
class SingleFrameCodec implements ui.Codec {
  SingleFrameCodec(this._image);

  final ui.Image _image;

  @override
  int get frameCount => 1;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() async => SingleFrameInfo(_image.clone());

  @override
  void dispose() => _image.dispose();
}

class SingleFrameInfo implements ui.FrameInfo {
  const SingleFrameInfo(this.image);

  @override
  final ui.Image image;

  @override
  Duration get duration => Duration.zero;
}
