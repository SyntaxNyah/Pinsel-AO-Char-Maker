import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../platform/workspace.dart';
import 'codecs.dart';
import 'color_ops.dart';
import 'webp_codec.dart';

typedef BulkProgress = void Function(int done, int total, String label);

/// Outcome for one processed file.
class BulkResult {
  BulkResult(this.sourceRel, {this.ok = true, this.outRel, this.error});
  final String sourceRel;
  final bool ok;
  final String? outRel;
  final String? error;
}

/// Target output format for a bulk run.
enum OutputFormat { keep, png, apng, gif, webp }

/// Applies a [ColorOp] pipeline and/or a format conversion across many files.
///
/// Powers "recolour every sprite", palette swaps for OCs, and on-page format
/// conversion (including WebP via [WebpEncoder]). Animation frames are
/// preserved for PNG/APNG/GIF; WebP currently exports the first frame.
class BulkProcessor {
  BulkProcessor(this.workspace);

  final Workspace workspace;

  Future<List<BulkResult>> run({
    required List<String> files,
    List<ColorOp> pipeline = const <ColorOp>[],
    OutputFormat output = OutputFormat.keep,
    bool webpLossless = false,
    int webpQuality = 90,
    bool inPlace = true,
    String nameSuffix = '',
    bool deleteOriginalOnConvert = false,
    BulkProgress? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final List<BulkResult> results = <BulkResult>[];
    int done = 0;
    for (final String rel in files) {
      // Cooperative cancellation: stop cleanly between files (everything already
      // written stays written; nothing is rolled back).
      if (shouldCancel != null && shouldCancel()) break;
      try {
        final BulkResult r = await _one(
          rel,
          pipeline: pipeline,
          output: output,
          webpLossless: webpLossless,
          webpQuality: webpQuality,
          inPlace: inPlace,
          nameSuffix: nameSuffix,
          deleteOriginalOnConvert: deleteOriginalOnConvert,
        );
        results.add(r);
      } catch (e) {
        results.add(BulkResult(rel, ok: false, error: '$e'));
      }
      onProgress?.call(++done, files.length, rel);
      // Yield periodically so the UI repaints (progress) and stays responsive.
      if (done % 4 == 0) await Future<void>.delayed(Duration.zero);
    }
    return results;
  }

  Future<BulkResult> _one(
    String rel, {
    required List<ColorOp> pipeline,
    required OutputFormat output,
    required bool webpLossless,
    required int webpQuality,
    required bool inPlace,
    required String nameSuffix,
    required bool deleteOriginalOnConvert,
  }) async {
    final String ext = p.extension(rel).replaceFirst('.', '').toLowerCase();
    final Uint8List bytes = await workspace.readBytes(rel);
    final img.Image? image = Codecs.decode(bytes, ext: ext);
    if (image == null) {
      return BulkResult(rel, ok: false, error: 'Could not decode');
    }

    if (pipeline.isNotEmpty) ImageOps.applyAll(image, pipeline);

    final String targetExt = _targetExt(ext, output);
    Uint8List outBytes;
    if (targetExt == 'webp') {
      final WebpResult wr = image.frames.length > 1
          ? await WebpEncoder.instance.encodeAnimation(
              image.frames.toList(),
              image.frames
                  .map((img.Image fr) => fr.frameDuration <= 0 ? 100 : fr.frameDuration)
                  .toList(),
              lossless: webpLossless,
              quality: webpQuality,
            )
          : await WebpEncoder.instance
              .encode(image, lossless: webpLossless, quality: webpQuality);
      if (!wr.ok) return BulkResult(rel, ok: false, error: wr.reason);
      outBytes = wr.bytes!;
    } else {
      outBytes = Codecs.encodeForExtension(image, targetExt);
    }

    final String outRel = _outPath(rel, targetExt, inPlace, nameSuffix);
    await workspace.writeBytes(outRel, outBytes);

    if (deleteOriginalOnConvert && outRel != rel) {
      await workspace.delete(rel);
    }
    return BulkResult(rel, ok: true, outRel: outRel);
  }

  String _targetExt(String sourceExt, OutputFormat output) {
    switch (output) {
      case OutputFormat.keep:
        return Codecs.outputExtensionFor(sourceExt);
      case OutputFormat.png:
        return 'png';
      case OutputFormat.apng:
        return 'apng';
      case OutputFormat.gif:
        return 'gif';
      case OutputFormat.webp:
        return 'webp';
    }
  }

  String _outPath(String rel, String ext, bool inPlace, String suffix) {
    final String dir = p.dirname(rel);
    final String base = p.basenameWithoutExtension(rel);
    final String name = '$base$suffix.$ext';
    final String joined = dir == '.' ? name : '$dir/$name';
    return Workspace.norm(joined);
  }
}
