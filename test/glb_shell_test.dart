import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/room_shell.dart';

List<Offset> rectRing(double wCm, double hCm) =>
    [Offset.zero, Offset(wCm, 0), Offset(wCm, hCm), Offset(0, hCm)];

void main() {
  const floor =
      FloorFinish(type: FloorFinishType.woodPlanks, colorArgb: 0xFFB08D6B);
  const wall = WallFinish(type: WallFinishType.paint, colorArgb: 0xFFE9E4DA);

  List<List<double>> readPositions(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final jsonLen = data.getUint32(12, Endian.little);
    final json = jsonDecode(String.fromCharCodes(
        bytes.sublist(12 + 8, 12 + 8 + jsonLen))) as Map<String, dynamic>;
    final accessor = (json['accessors'] as List).first as Map<String, dynamic>;
    final bufferViews = json['bufferViews'] as List;
    final stride = ((bufferViews.first as Map<String, dynamic>)['byteStride']
            as int?) ??
        36;
    final count = accessor['count'] as int;
    final off = 12 + 8 + jsonLen + 8;
    final pts = <List<double>>[];
    for (var i = 0; i < count; i++) {
      final at = off + i * stride;
      pts.add([
        data.getFloat32(at, Endian.little),
        data.getFloat32(at + 4, Endian.little),
        data.getFloat32(at + 8, Endian.little),
      ]);
    }
    return pts;
  }

  group('generateRoomShellGlb', () {
    test('rectangular room: bounds match ring + wall thickness + height', () {
      final shell = ShellGeometry(ringCm: rectRing(400, 300));
      final b = GlbBounds.fromGlbBytes(
          generateRoomShellGlb(shell: shell, floor: floor, wall: wall));
      expect(b.widthM, closeTo(4.2, 0.03), reason: '4.0 m ring + 2 × 10 cm');
      expect(b.depthM, closeTo(3.2, 0.03), reason: '3.0 m ring + 2 × 10 cm');
      expect(b.heightM, closeTo(2.70, 0.02), reason: 'wall height');
      expect(b.minY, closeTo(0, 1e-6), reason: 'nothing below the floor');
    });

    test('no pattern vertex escapes the shell bounds (L-shaped room)', () {
      final shell = ShellGeometry(ringCm: [
        const Offset(0, 0),
        const Offset(400, 0),
        const Offset(400, 260),
        const Offset(150, 260),
        const Offset(150, 120),
        const Offset(0, 120),
      ]);
      final bytes =
          generateRoomShellGlb(shell: shell, floor: floor, wall: wall);
      final b = GlbBounds.fromGlbBytes(bytes);
      final bounds = shell.boundsCm;
      expect(b.minX, greaterThanOrEqualTo(bounds.left / 100 - 0.01));
      expect(b.maxX, lessThanOrEqualTo(bounds.right / 100 + 0.01));
      expect(b.minZ, greaterThanOrEqualTo(bounds.top / 100 - 0.01));
      expect(b.maxZ, lessThanOrEqualTo(bounds.bottom / 100 + 0.01));
      expect(b.minY, greaterThanOrEqualTo(-0.001));
      expect(b.maxY, lessThanOrEqualTo(2.71));
    });

    test('baseboards stand 8 cm tall along the wall line', () {
      final shell = ShellGeometry(ringCm: rectRing(300, 300));
      final pts = readPositions(
          generateRoomShellGlb(shell: shell, floor: floor, wall: wall));
      final inBand = pts.where((p) => p[1] > 0.075 && p[1] < 0.085).length;
      expect(inBand, greaterThan(0),
          reason: 'baseboard trim vertices at y ≈ 0.08 m');
    });

    test('floor pattern tiers float above the exact floor', () {
      final shell = ShellGeometry(ringCm: rectRing(320, 260));
      final pts = readPositions(
          generateRoomShellGlb(shell: shell, floor: floor, wall: wall));
      final pattern =
          pts.where((p) => p[1] > 0.0005 && p[1] < 0.005).length;
      expect(pattern, greaterThan(20),
          reason: 'plank/grain quads at y ≈ 1–2 mm');
    });

    test('every floor and wall finish type generates', () {
      final shell = ShellGeometry(ringCm: rectRing(320, 260));
      for (final type in FloorFinishType.values) {
        final b = GlbBounds.fromGlbBytes(generateRoomShellGlb(
          shell: shell,
          floor: FloorFinish(type: type, colorArgb: 0xFFB08D6B),
          wall: wall,
        ));
        expect(b.widthM, greaterThan(3), reason: type.name);
      }
      for (final type in WallFinishType.values) {
        final b = GlbBounds.fromGlbBytes(generateRoomShellGlb(
          shell: shell,
          floor: floor,
          wall: WallFinish(type: type, colorArgb: 0xFFE9E4DA),
        ));
        expect(b.heightM, closeTo(2.70, 0.02), reason: type.name);
      }
    });

    test('same finishes regenerate byte-identically; a change does not', () {
      final shell = ShellGeometry(ringCm: rectRing(300, 300));
      Uint8List gen() => generateRoomShellGlb(shell: shell, floor: floor, wall: wall);
      expect(gen(), gen());
      final other = generateRoomShellGlb(
        shell: shell,
        floor: const FloorFinish(
            type: FloorFinishType.ceramicTiles, colorArgb: 0xFFD8D2C0),
        wall: wall,
      );
      expect(other, isNot(gen()));
    });

    test('degenerate rings are rejected', () {
      expect(
        () => generateRoomShellGlb(
          shell: ShellGeometry(ringCm: const [Offset(0, 0), Offset(100, 0)]),
          floor: floor,
          wall: wall,
        ),
        throwsArgumentError,
      );
    });
  });

  group('generateRoomShellGlb (dollhouse cutaway)', () {
    test('a fully cut shell drops to the cutaway height', () {
      final shell = ShellGeometry(ringCm: rectRing(400, 300));
      final b = GlbBounds.fromGlbBytes(generateRoomShellGlb(
        shell: shell,
        floor: floor,
        wall: wall,
        cutMask: const [true, true, true, true],
      ));
      expect(b.heightM, closeTo(1.2, 0.02), reason: 'kShellCutawayHeightCm');
    });

    test('far walls keep full height while cut runs end low', () {
      final shell = ShellGeometry(ringCm: rectRing(400, 300));
      final bytes = generateRoomShellGlb(
        shell: shell,
        floor: floor,
        wall: wall,
        cutMask: const [true, false, true, false],
      );
      final b = GlbBounds.fromGlbBytes(bytes);
      expect(b.heightM, closeTo(2.7, 0.02), reason: 'far walls stay full');
      final cutTops =
          readPositions(bytes).where((p) => p[1] > 1.19 && p[1] < 1.21).length;
      expect(cutTops, greaterThan(0), reason: 'cut runs end at 1.2 m');
    });

    test('the camera-side mask drives generation and stays deterministic', () {
      final shell = ShellGeometry(ringCm: rectRing(400, 300));
      const near = Offset(200, -150); // outside the bottom run
      expect(cutawaySignature(shell, near), '1000');
      Uint8List gen() => generateRoomShellGlb(
          shell: shell,
          floor: floor,
          wall: wall,
          cutMask: cutawayMask(shell, near));
      expect(gen(), gen());
      final other = generateRoomShellGlb(
        shell: shell,
        floor: floor,
        wall: wall,
        cutMask: cutawayMask(shell, const Offset(200, 450)), // outside top
      );
      expect(other, isNot(gen()), reason: 'a mask flip regenerates');
    });
  });
}
