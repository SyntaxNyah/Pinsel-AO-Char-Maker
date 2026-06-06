import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/ao_constants.dart';

/// Decode/encode helpers that understand every format AO uses (and many it
/// doesn't), preserving animation frames where present.
///
/// Decoding is format-agnostic: webp/apng/gif/png plus jpg/bmp/tga/tiff/etc.
/// Encoding targets AO-compatible outputs: PNG (static), APNG and GIF (animated).
class Codecs {
  const Codecs._();

  /// Decode bytes into an [img.Image]. For animated formats the returned image
  /// carries every frame in [img.Image.frames]. Returns null on failure.
  static img.Image? decode(Uint8List bytes, {String? ext}) {
    try {
      if (ext != null && ext.isNotEmpty) {
        final img.Image? named = img.decodeNamedImage('x.$ext', bytes);
        if (named != null) return named;
      }
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Decode just the first frame (fast path for static previews and buttons).
  ///
  /// Perf: this asks the decoder for **frame 0 only** (`decodeImage(..,
  /// frame: 0)`) instead of decoding the whole animation and throwing away the
  /// rest. AO's default sprites are animated WebP, and previews / button
  /// thumbnails / head-square + mouth seeding all funnel through here, so
  /// skipping the other frames is a large saving on a big cast. Falls back to a
  /// full decode (then the first frame) if the fast path can't handle the bytes.
  static img.Image? decodeFirstFrame(Uint8List bytes, {String? ext}) {
    try {
      final img.Image? first = img.decodeImage(bytes, frame: 0);
      if (first != null) return first;
    } catch (_) {
      // Fall through to the tolerant full decode below.
    }
    final img.Image? full = decode(bytes, ext: ext);
    if (full == null) return null;
    return full.frames.isNotEmpty ? full.frames.first : full;
  }

  static bool isAnimatedExt(String ext) =>
      kAnimatedExtensions.contains(ext.toLowerCase());

  static int frameCount(img.Image image) =>
      image.frames.isEmpty ? 1 : image.frames.length;

  /// Encode a (possibly multi-frame) image to PNG/APNG.
  static Uint8List encodePng(img.Image image) =>
      Uint8List.fromList(img.encodePng(image));

  /// Encode to animated GIF (falls back to a single frame if static).
  static Uint8List encodeGif(img.Image image) =>
      Uint8List.fromList(img.encodeGif(image));

  /// Encode preserving animation: APNG for animated input written as `.apng`,
  /// GIF for `.gif`, otherwise PNG. WebP *encoding* is not yet available in
  /// pure Dart, so animated webp is re-emitted as APNG (lossless, AO-supported).
  static Uint8List encodeForExtension(img.Image image, String ext) {
    final String e = ext.toLowerCase();
    if (e == 'gif') return encodeGif(image);
    // PNG encoder writes APNG automatically when multiple frames are present.
    return encodePng(image);
  }

  /// The AO-compatible output extension we will actually write for a given
  /// source extension (honours the webp -> apng substitution above).
  static String outputExtensionFor(String sourceExt) {
    final String e = sourceExt.toLowerCase();
    if (e == 'gif') return 'gif';
    if (e == 'apng' || e == 'webp') return 'apng';
    return 'png';
  }
}
