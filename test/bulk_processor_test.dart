import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/imaging/bulk_processor.dart';
import 'package:pinsel/src/imaging/codecs.dart';
import 'package:pinsel/src/platform/workspace.dart';

/// A few tiny PNG files in a fresh in-memory workspace.
({MemoryWorkspace ws, List<String> files}) _seed(int n) {
  final MemoryWorkspace ws = MemoryWorkspace();
  final Uint8List png =
      Codecs.encodePng(img.Image(width: 4, height: 4, numChannels: 4));
  final List<String> files = <String>[];
  for (int i = 0; i < n; i++) {
    final String rel = 's$i.png';
    ws.put(rel, png);
    files.add(rel);
  }
  return (ws: ws, files: files);
}

void main() {
  group('BulkProcessor cancellation', () {
    test('shouldCancel stops cleanly between files', () async {
      final ({MemoryWorkspace ws, List<String> files}) s = _seed(6);
      int done = 0;
      final List<BulkResult> res = await BulkProcessor(s.ws).run(
        files: s.files,
        output: OutputFormat.png,
        onProgress: (int d, int t, String l) => done = d,
        shouldCancel: () => done >= 3, // stop once 3 are processed
      );
      // It checks before each file, so it processes exactly 3 then breaks.
      expect(res.length, 3);
      expect(res.every((BulkResult r) => r.ok), isTrue);
      expect(done, 3);
    });

    test('without shouldCancel it processes everything', () async {
      final ({MemoryWorkspace ws, List<String> files}) s = _seed(6);
      final List<BulkResult> res = await BulkProcessor(s.ws).run(
        files: s.files,
        output: OutputFormat.png,
      );
      expect(res.length, 6);
      expect(res.every((BulkResult r) => r.ok), isTrue);
    });

    test('shouldCancel true from the start does nothing', () async {
      final ({MemoryWorkspace ws, List<String> files}) s = _seed(4);
      final List<BulkResult> res = await BulkProcessor(s.ws).run(
        files: s.files,
        output: OutputFormat.png,
        shouldCancel: () => true,
      );
      expect(res, isEmpty);
    });
  });
}
