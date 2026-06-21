import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/puppet/puppet.dart';

img.Image _solid(int w, int h, {int r = 255, int g = 0, int b = 0}) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(r, g, b, 255));
  return im;
}

bool _anyFrameDiffers(List<img.Image> frames) {
  final img.Image first = frames.first;
  for (int i = 1; i < frames.length; i++) {
    final img.Image f = frames[i];
    for (int y = 0; y < first.height; y++) {
      for (int x = 0; x < first.width; x++) {
        final img.Pixel a = first.getPixel(x, y);
        final img.Pixel b = f.getPixel(x, y);
        if (a.r != b.r || a.g != b.g || a.b != b.b || a.a != b.a) return true;
      }
    }
  }
  return false;
}

void main() {
  test('a static layer lands centred on its (x,y) pivot', () {
    final PuppetRig rig = PuppetRig(width: 100, height: 100, layers: <PuppetLayer>[
      PuppetLayer(_solid(10, 10), x: 0.25, y: 0.75, pivotX: 0.5, pivotY: 0.5),
    ]);
    final clip = PuppetEngine.render(rig, frames: 8);
    expect(clip.frames.length, 1); // no motion ⇒ collapsed to a single still
    final img.Image f = clip.frames.first.image;
    expect(f.width, 100);
    expect(f.height, 100);
    // The 10×10 block is centred at (25,75): centre opaque, far corner clear.
    expect(f.getPixel(25, 75).a, greaterThan(0));
    expect(f.getPixel(75, 25).a, 0);
  });

  test('a top-pivoted layer hangs below its anchor (catches a pivot sign error)',
      () {
    final PuppetRig rig = PuppetRig(width: 100, height: 100, layers: <PuppetLayer>[
      PuppetLayer(_solid(10, 10), x: 0.5, y: 0.5, pivotX: 0.5, pivotY: 0.0),
    ]);
    final img.Image f = PuppetEngine.render(rig).frames.first.image;
    // Pivot is the part's TOP, anchored at y=50 ⇒ the block hangs downward.
    expect(f.getPixel(50, 55).a, greaterThan(0)); // below the pivot = painted
    expect(f.getPixel(50, 44).a, 0); // above the pivot = clear
  });

  test('idle and talk clips share dimensions + frame count', () {
    final PuppetRig rig = PuppetRig(width: 64, height: 64, layers: <PuppetLayer>[
      PuppetLayer.withRoleDefaults(_solid(40, 50, g: 200, r: 0),
          name: 'body', role: PuppetRole.body, x: 0.5, y: 0.7),
      PuppetLayer.withRoleDefaults(_solid(16, 8),
          name: 'mouth', role: PuppetRole.mouth, x: 0.5, y: 0.4),
    ]);
    final idle = PuppetEngine.render(rig, frames: 8, talk: false);
    final talk = PuppetEngine.render(rig, frames: 8, talk: true);
    // AO jumps between (a) idle and (b) talk, so they MUST match exactly.
    expect(idle.frames.length, 8);
    expect(talk.frames.length, idle.frames.length);
    expect(idle.width, talk.width);
    expect(idle.height, talk.height);
    expect(idle.width, 64);
    expect(idle.height, 64);
    // Even, seamless playback ⇒ one shared frame delay.
    expect(talk.frames.map((f) => f.delayCentis).toSet().length, 1);
  });

  test('talk actually moves a mouth layer', () {
    final PuppetRig rig = PuppetRig(width: 64, height: 64, layers: <PuppetLayer>[
      PuppetLayer.withRoleDefaults(_solid(20, 10),
          name: 'mouth', role: PuppetRole.mouth, x: 0.5, y: 0.5),
    ]);
    final talk = PuppetEngine.render(rig, frames: 8, talk: true);
    expect(talk.frames.length, 8); // mouth + talk animates even with no idle motion
    expect(_anyFrameDiffers(talk.frames.map((f) => f.image).toList()), isTrue);
  });

  test('a fully static rig collapses to one frame; motion gives many', () {
    final PuppetRig still = PuppetRig(
        width: 32, height: 32, layers: <PuppetLayer>[PuppetLayer(_solid(8, 8))]);
    expect(PuppetEngine.render(still, frames: 12).frames.length, 1);

    final PuppetRig moving = PuppetRig(width: 32, height: 32, layers: <PuppetLayer>[
      PuppetLayer.withRoleDefaults(_solid(8, 8),
          name: 'hair', role: PuppetRole.hair),
    ]);
    // A phased, moving layer still produces a full, clean loop.
    final clip = PuppetEngine.render(moving, frames: 12);
    expect(clip.frames.length, 12);
    expect(clip.frames.map((f) => f.delayCentis).toSet().length, 1);
  });

  test('scale renders a proportionally smaller clip (the preview perf path)', () {
    final PuppetRig rig = PuppetRig(width: 200, height: 100, layers: <PuppetLayer>[
      PuppetLayer.withRoleDefaults(_solid(40, 40),
          name: 'hair', role: PuppetRole.hair),
    ]);
    final full = PuppetEngine.render(rig, frames: 4);
    final half = PuppetEngine.render(rig, frames: 4, scale: 0.5);
    expect(full.width, 200);
    expect(full.height, 100);
    expect(half.width, 100); // canvas halved
    expect(half.height, 50);
    expect(half.frames.length, full.frames.length); // same frame count
  });
}
