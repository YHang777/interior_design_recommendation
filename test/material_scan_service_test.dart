import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart'
    show FloorFinishType, WallFinishType;
import 'package:interior_design_recommendation/features/customer/ar/data/room_finishes.dart';
import 'package:interior_design_recommendation/services/material_scan_service.dart';

void main() {
  group('parseMaterialScanJson', () {
    test('maps the verdict onto catalog types and palette colors', () {
      final scan = parseMaterialScanJson({
        'status': 'ok',
        'floor': {'material': 'woodPlanks', 'hex': '#B08D6B'},
        'wall': {'material': 'paint', 'hex': '#F5F3EE'},
      });
      expect(scan, isNotNull);
      expect(scan!.floorType, FloorFinishType.woodPlanks);
      expect(
        scan.floorColorArgb,
        RoomFinishCatalog.colorsForFloor(FloorFinishType.woodPlanks)
            .firstWhere((c) => c.name == 'Oak')
            .argb,
      );
      expect(scan.wallType, WallFinishType.paint);
      expect(
        scan.wallColorArgb,
        RoomFinishCatalog.colorsForWall(WallFinishType.paint)
            .firstWhere((c) => c.name == 'White')
            .argb,
      );
    });

    test('snaps an off-palette hex onto the nearest swatch of the type', () {
      final scan = parseMaterialScanJson({
        'status': 'ok',
        'floor': {'material': 'parquet', 'hex': '#7A5238'},
      });
      expect(scan!.floorType, FloorFinishType.parquet);
      expect(
        RoomFinishCatalog.colorName(
          scan.floorColorArgb!,
          RoomFinishCatalog.colorsForFloor(FloorFinishType.parquet),
        ),
        'Cognac',
      );
    });

    test('a type without a hex falls back to its palette default', () {
      final scan = parseMaterialScanJson({
        'status': 'ok',
        'wall': {'material': 'woodPanels'},
      });
      expect(scan!.wallType, WallFinishType.woodPanels);
      expect(
        scan.wallColorArgb,
        RoomFinishCatalog.defaultArgbForWall(WallFinishType.woodPanels),
      );
    });

    test('unknown surfaces are kept out and both-unknown is null', () {
      final mixed = parseMaterialScanJson({
        'status': 'ok',
        'floor': {'material': 'woodPlanks', 'hex': '#B08D6B'},
        'wall': {'material': 'unknown', 'hex': ''},
      });
      expect(mixed!.floorType, FloorFinishType.woodPlanks);
      expect(mixed.wallType, isNull);
      expect(mixed.wallColorArgb, isNull);
      expect(mixed.isEmpty, isFalse);

      expect(
        parseMaterialScanJson({
          'status': 'ok',
          'floor': {'material': 'marble'},
          'wall': {'material': 'wallpaper'},
        }),
        isNull,
      );
    });

    test('a failed or malformed body never invents a finish', () {
      expect(parseMaterialScanJson({'status': 'failed'}), isNull);
      expect(parseMaterialScanJson({'status': 'ok'}), isNull);
      expect(parseMaterialScanJson({'floor': []}), isNull);
    });
  });

  group('argbFromHex', () {
    test('parses #RGB, #RRGGBB and bare hex, rejects the rest', () {
      expect(argbFromHex('#B08D6B'), 0xFFB08D6B);
      expect(argbFromHex('b08d6b'), 0xFFB08D6B);
      expect(argbFromHex('#fff'), 0xFFFFFFFF);
      expect(argbFromHex(''), isNull);
      expect(argbFromHex('#12345'), isNull);
      expect(argbFromHex('rgb(1,2,3)'), isNull);
    });
  });

  group('MaterialScanService.analyzeFrame', () {
    final jpeg = Uint8List.fromList([1, 2, 3, 4]);

    MaterialScanService service(
      MockClient client, {
      Future<String?> Function()? idTokenProvider,
    }) =>
        MaterialScanService(
          client: client,
          idTokenProvider: idTokenProvider ?? () async => 'test-token',
        );

    test('posts the frame as base64 with the id token', () async {
      http.Request? seen;
      final svc = service(MockClient((request) async {
        seen = http.Request(request.method, request.url)
          ..bodyBytes = request.bodyBytes
          ..headers.addAll(request.headers);
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'floor': {'material': 'woodPlanks', 'hex': '#B08D6B'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }));

      final scan = await svc.analyzeFrame(jpeg);
      expect(scan, isNotNull);
      expect(scan!.floorType, FloorFinishType.woodPlanks);

      expect(seen, isNotNull);
      expect(seen!.url.path, '/api/ai/analyze-room-material');
      expect(seen!.headers['Authorization'], 'Bearer test-token');
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['imageBase64'], base64Encode(jpeg));
      expect(body['mimeType'], 'image/jpeg');
    });

    test('a server "failed" verdict surfaces its short sentence', () async {
      final svc = service(MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'failed',
            'message': 'We could not read the floor and wall in this frame.',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }));

      await expectLater(
        svc.analyzeFrame(jpeg),
        throwsA(isA<MaterialScanException>().having(
          (e) => e.userMessage,
          'userMessage',
          'We could not read the floor and wall in this frame.',
        )),
      );
    });

    test('status codes map to short user sentences', () async {
      Future<String> messageFor(int status) async {
        final svc = service(MockClient((request) async {
          return http.Response('nope', status);
        }));
        try {
          await svc.analyzeFrame(jpeg);
          return 'no-throw';
        } on MaterialScanException catch (e) {
          return e.userMessage;
        }
      }

      expect(await messageFor(401), 'Please sign in to scan materials.');
      expect(await messageFor(503), 'Room material scan is not set up yet.');
      expect(await messageFor(500),
          'We could not read the room materials right now.');
    });

    test('an empty frame never calls the backend', () async {
      var called = false;
      final svc = service(MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }));
      expect(await svc.analyzeFrame(Uint8List(0)), isNull);
      expect(called, isFalse);
    });

    test('a missing id token asks the user to sign in', () async {
      final svc = service(
        MockClient((request) async => http.Response('{}', 200)),
        idTokenProvider: () async => null,
      );
      await expectLater(
        svc.analyzeFrame(jpeg),
        throwsA(isA<MaterialScanException>().having(
          (e) => e.userMessage,
          'userMessage',
          'Please sign in to scan materials.',
        )),
      );
    });
  });
}
