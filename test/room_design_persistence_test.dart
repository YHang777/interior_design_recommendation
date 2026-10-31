import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/supabase_room_design_datasource.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

void main() {
  RoomDesign design({List<Offset> walls = const []}) => RoomDesign(
        id: 'd1',
        name: 'My Room',
        roomType: 'living_room',
        widthCm: 400,
        heightCm: 500,
        furniture: const [
          FurniturePlacement(
            id: 'sofa-1',
            name: 'Sofa',
            iconName: 'sofa',
            x: 40,
            y: 40,
            width: 180,
            height: 90,
            rotation: 90,
          ),
        ],
        walls: walls,
        detectedItems: const ['sofa'],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        userId: 'u1',
      );

  test('RoomDesign round-trips walls and rotated furniture through JSON',
      () {
    final original = design(walls: const [
      Offset(30, 30),
      Offset(370, 30),
      Offset(200, 450),
    ]);

    final restored = RoomDesign.fromJson(original.toJson());

    expect(restored.walls.length, 3);
    expect(restored.walls[0], const Offset(30, 30));
    expect(restored.walls[2], const Offset(200, 450));
    expect(restored.furniture.single.rotation, 90);
    expect(restored.name, 'My Room');
  });

  test('legacy rows with a plain furniture array load with no walls', () {
    final restored = RoomDesign.fromJson({
      'id': 'd2',
      'name': 'Legacy',
      'roomType': 'bedroom',
      'widthCm': 300,
      'heightCm': 400,
      'furniture': [
        {
          'id': 'bed-1',
          'name': 'Bed',
          'iconName': 'bed',
          'x': 10.0,
          'y': 10.0,
          'width': 200.0,
          'height': 160.0,
          'rotation': 0,
        }
      ],
      'userId': 'u1',
    });

    expect(restored.furniture.single.name, 'Bed');
    expect(restored.walls, isEmpty);
  });

  test('rows with furniture embedded as {items, walls} load both', () {
    final restored = RoomDesign.fromJson({
      'id': 'd3',
      'name': 'Embedded',
      'roomType': 'kitchen',
      'widthCm': 350,
      'heightCm': 420,
      'furniture': {
        'items': [
          {
            'id': 'table-1',
            'name': 'Dining Table',
            'iconName': 'dining_table',
            'x': 20.0,
            'y': 30.0,
            'width': 140.0,
            'height': 100.0,
            'rotation': 0,
          }
        ],
        'walls': [
          [15, 15],
          [335, 15],
          [335, 405],
          [15, 405],
        ],
      },
      'userId': 'u1',
    });

    expect(restored.furniture.single.name, 'Dining Table');
    expect(restored.walls.length, 4);
    expect(restored.walls.first, const Offset(15, 15));
  });

  group('SupabaseRoomDesignDatasource', () {
    late List<http.Request> sent;
    late SupabaseRoomDesignDatasource ds;

    setUp(() {
      sent = [];
      ds = SupabaseRoomDesignDatasource(
        client: MockClient((request) async {
          sent.add(http.Request(request.method, request.url)
            ..bodyBytes = request.bodyBytes);
          return http.Response('{}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );
    });

    test('createDesign sends snake_case columns and embeds walls in furniture',
        () async {
      await ds.createDesign(
        designId: 'd1',
        data: design(walls: const [Offset(30, 30), Offset(370, 30)]).toJson(),
      );

      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;

      expect(body['room_type'], 'living_room');
      expect(body['width_cm'], 400);
      expect(body['height_cm'], 500);
      expect(body['detected_items'], ['sofa']);
      expect(body['user_id'], 'u1');

      // No camelCase leftovers — PostgREST rejects unknown columns.
      expect(body.containsKey('roomType'), isFalse);
      expect(body.containsKey('widthCm'), isFalse);
      expect(body.containsKey('heightCm'), isFalse);
      expect(body.containsKey('detectedItems'), isFalse);
      expect(body.containsKey('userId'), isFalse);
      expect(body.containsKey('walls'), isFalse);

      final furniture = body['furniture'] as Map<String, dynamic>;
      expect((furniture['items'] as List), hasLength(1));
      expect(furniture['walls'], [
        [30, 30],
        [370, 30],
      ]);
    });

    test('updateDesign maps columns the same way', () async {
      await ds.updateDesign(
        'd1',
        design(walls: const [Offset(1, 2)]).toJson(),
      );

      expect(sent.single.method, 'PATCH');
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['room_type'], 'living_room');
      expect(body.containsKey('widthCm'), isFalse);
      final furniture = body['furniture'] as Map<String, dynamic>;
      expect(furniture['walls'], [
        [1, 2]
      ]);
    });

    test('getDesign reads back an embedded row', () async {
      ds = SupabaseRoomDesignDatasource(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode([
              {
                'id': 'd9',
                'name': 'Round Trip',
                'room_type': 'office',
                'width_cm': 320,
                'height_cm': 480,
                'furniture': {
                  'items': [
                    {
                      'id': 'desk-1',
                      'name': 'Desk',
                      'iconName': 'desk',
                      'x': 50.0,
                      'y': 60.0,
                      'width': 120.0,
                      'height': 60.0,
                      'rotation': 0,
                    }
                  ],
                  'walls': [
                    [10, 10],
                    [310, 10],
                    [310, 470],
                  ],
                },
                'detected_items': ['desk'],
                'image_path': null,
                'created_at': '2026-01-01T00:00:00Z',
                'updated_at': '2026-01-02T00:00:00Z',
                'user_id': 'u1',
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final loaded = await ds.getDesign('d9');
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Round Trip');
      expect(loaded.roomType, 'office');
      expect(loaded.widthCm, 320);
      expect(loaded.furniture.single.name, 'Desk');
      expect(loaded.walls.length, 3);
      expect(loaded.walls[1], const Offset(310, 10));
    });

    test('network errors propagate as typed exceptions for userMessage',
        () async {
      ds = SupabaseRoomDesignDatasource(
        client: MockClient((request) async {
          throw http.ClientException('connection refused');
        }),
      );

      await expectLater(
        ds.createDesign(designId: 'd1', data: design().toJson()),
        throwsA(isA<http.ClientException>()),
      );
    });
  });
}
