/// A furniture item placed on a room floor plan.
class FurniturePlacement {
  final String id;
  final String name;
  final String iconName;
  final double x; // cm offset from left
  final double y; // cm offset from top
  final double width; // cm
  final double height; // cm
  final double rotation; // degrees (0–360)
  final String? imageAsset;

  const FurniturePlacement({
    required this.id,
    required this.name,
    required this.iconName,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.imageAsset,
  });

  FurniturePlacement copyWith({
    String? id,
    String? name,
    String? iconName,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    String? imageAsset,
    bool clearImageAsset = false,
  }) {
    return FurniturePlacement(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      imageAsset: clearImageAsset ? null : (imageAsset ?? this.imageAsset),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'name': name,
      'iconName': iconName,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
    };
    if (imageAsset != null) m['imageAsset'] = imageAsset;
    return m;
  }

  factory FurniturePlacement.fromJson(Map<String, dynamic> json) {
    return FurniturePlacement(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      iconName: json['iconName']?.toString() ?? '',
      x: (json['x'] is num) ? (json['x'] as num).toDouble() : 0.0,
      y: (json['y'] is num) ? (json['y'] as num).toDouble() : 0.0,
      width: (json['width'] is num) ? (json['width'] as num).toDouble() : 80.0,
      height:
          (json['height'] is num) ? (json['height'] as num).toDouble() : 60.0,
      rotation:
          (json['rotation'] is num) ? (json['rotation'] as num).toDouble() : 0,
      imageAsset: json['imageAsset']?.toString(),
    );
  }
}

/// A saved room design with furniture layout.
class RoomDesign {
  final String id;
  final String name;
  final String roomType; // living_room, bedroom, kitchen, bathroom, dining_room, home_office
  final double widthCm;
  final double heightCm;
  final List<FurniturePlacement> furniture;
  final List<String> detectedItems;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String userId;

  const RoomDesign({
    required this.id,
    required this.name,
    required this.roomType,
    this.widthCm = 400,
    this.heightCm = 500,
    this.furniture = const [],
    this.detectedItems = const [],
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
  });

  RoomDesign copyWith({
    String? id,
    String? name,
    String? roomType,
    double? widthCm,
    double? heightCm,
    List<FurniturePlacement>? furniture,
    List<String>? detectedItems,
    String? imagePath,
    bool clearImagePath = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userId,
  }) {
    return RoomDesign(
      id: id ?? this.id,
      name: name ?? this.name,
      roomType: roomType ?? this.roomType,
      widthCm: widthCm ?? this.widthCm,
      heightCm: heightCm ?? this.heightCm,
      furniture: furniture ?? this.furniture,
      detectedItems: detectedItems ?? this.detectedItems,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userId: userId ?? this.userId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'roomType': roomType,
        'widthCm': widthCm,
        'heightCm': heightCm,
        'furniture': furniture.map((f) => f.toJson()).toList(),
        'detectedItems': detectedItems,
        if (imagePath != null) 'imagePath': imagePath,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'userId': userId,
      };

  factory RoomDesign.fromJson(Map<String, dynamic> json) {
    return RoomDesign(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Design',
      roomType: json['roomType']?.toString() ?? 'living_room',
      widthCm: (json['widthCm'] is num)
          ? (json['widthCm'] as num).toDouble()
          : 400,
      heightCm: (json['heightCm'] is num)
          ? (json['heightCm'] as num).toDouble()
          : 500,
      furniture: (json['furniture'] is List)
          ? (json['furniture'] as List<dynamic>)
              .map((e) =>
                  FurniturePlacement.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      detectedItems: (json['detectedItems'] is List)
          ? (json['detectedItems'] as List<dynamic>)
              .map((e) => e.toString())
              .toList()
          : [],
      imagePath: json['imagePath']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      userId: json['userId']?.toString() ?? '',
    );
  }

  /// Human-readable room type label.
  String get roomTypeLabel {
    switch (roomType) {
      case 'living_room':
        return 'Living Room';
      case 'bedroom':
        return 'Bedroom';
      case 'kitchen':
        return 'Kitchen';
      case 'bathroom':
        return 'Bathroom';
      case 'dining_room':
        return 'Dining Room';
      case 'home_office':
        return 'Home Office';
      default:
        return roomType;
    }
  }
}

/// A single entry in the furniture catalog.
class FurnitureCatalogItem {
  final String name;
  final String iconName;
  final String category;
  final double defaultWidth;
  final double defaultHeight;
  final String? imageAsset;
  final String? productId;

  const FurnitureCatalogItem({
    required this.name,
    required this.iconName,
    required this.category,
    this.defaultWidth = 80,
    this.defaultHeight = 60,
    this.imageAsset,
    this.productId,
  });
}
