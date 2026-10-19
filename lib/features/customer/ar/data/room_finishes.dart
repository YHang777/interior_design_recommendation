import 'glb_generator.dart' show FloorFinishType, WallFinishType;

class FinishColor {
  const FinishColor(this.name, this.argb);

  final String name;

  final int argb;

  @override
  String toString() => '$name (#${argb.toRadixString(16).padLeft(8, '0')})';
}

class FloorTypeSpec {
  const FloorTypeSpec({
    required this.label,
    required this.description,
    required this.colors,
  });

  final String label;

  final String description;

  final List<FinishColor> colors;
}

class WallTypeSpec {
  const WallTypeSpec({
    required this.label,
    required this.description,
    required this.colors,
  });

  final String label;
  final String description;
  final List<FinishColor> colors;
}

// ─── Shared color instances ──────────────────────────────────────────────────

const FinishColor _oak = FinishColor('Oak', 0xFFB08D6B);
const FinishColor _walnut = FinishColor('Walnut', 0xFF6B4A32);
const FinishColor _darkOak = FinishColor('Dark Oak', 0xFF46321F);
const FinishColor _greyWood = FinishColor('Grey', 0xFF9A948A);

const FinishColor _lightGrey = FinishColor('Light Grey', 0xFFC9C6BF);
const FinishColor _charcoal = FinishColor('Charcoal', 0xFF3E3E3C);
const FinishColor _beige = FinishColor('Beige', 0xFFC9B896);

const FinishColor _tileWhite = FinishColor('White', 0xFFF2F0EA);
const FinishColor _cream = FinishColor('Cream', 0xFFEAD9BE);
const FinishColor _tileGrey = FinishColor('Grey', 0xFFB1B6B8);
const FinishColor _terracotta = FinishColor('Terracotta', 0xFFA95F45);

const FinishColor _natural = FinishColor('Natural', 0xFFC9A368);
const FinishColor _honey = FinishColor('Honey', 0xFFD9B076);
const FinishColor _cognac = FinishColor('Cognac', 0xFF9C5A32);

const FinishColor _paintWhite = FinishColor('White', 0xFFF5F3EE);
const FinishColor _offWhite = FinishColor('Off-white', 0xFFE9E4D9);
const FinishColor _paintGrey = FinishColor('Grey', 0xFFB0B6BC);
const FinishColor _duckEgg = FinishColor('Duck Egg', 0xFFBCD2CE);
const FinishColor _navy = FinishColor('Navy', 0xFF22334D);

const FinishColor _whitewashed = FinishColor('Whitewashed', 0xFFDDD6C9);

const FinishColor _brickRed = FinishColor('Red', 0xFFA8442F);
const FinishColor _orangeBrick = FinishColor('Orange Brick', 0xFFBC6A41);
const FinishColor _whitePainted =
    FinishColor('White Painted', 0xFFE0D8CD);

class RoomFinishCatalog {
  RoomFinishCatalog._();

  // ─── Defaults ──────────────────────────────────────────────────────────────

  static const FloorFinishType defaultFloorType = FloorFinishType.woodPlanks;
  static const WallFinishType defaultWallType = WallFinishType.paint;

  static const int defaultFloorColorArgb = 0xFFB08D6B;
  static const int defaultWallColorArgb = 0xFFF5F3EE;

  static const List<double> floorSizeOptionsM = [2.0, 3.0, 4.0, -1.0];
  static const double defaultFloorSizeM = 3.0;

  static const double wallWidthM = 2.4;
  static const double wallHeightM = 2.7;

  // ─── The tables ────────────────────────────────────────────────────────────

  static const Map<FloorFinishType, FloorTypeSpec> floorTypes = {
    FloorFinishType.woodPlanks: FloorTypeSpec(
      label: 'Wood',
      description: 'Warm plank boards with staggered joints',
      colors: [_oak, _walnut, _darkOak, _greyWood],
    ),
    FloorFinishType.cement: FloorTypeSpec(
      label: 'Cement',
      description: 'Polished cement with subtle tonal variation',
      colors: [_lightGrey, _charcoal, _beige],
    ),
    FloorFinishType.ceramicTiles: FloorTypeSpec(
      label: 'Ceramic',
      description: 'Glossy ceramic tiles with fine grout lines',
      colors: [_tileWhite, _cream, _tileGrey, _terracotta],
    ),
    FloorFinishType.parquet: FloorTypeSpec(
      label: 'Parquet',
      description: 'Mini parquet blocks with diagonal tonal bands',
      colors: [_natural, _honey, _cognac],
    ),
  };

  static const Map<WallFinishType, WallTypeSpec> wallTypes = {
    WallFinishType.paint: WallTypeSpec(
      label: 'Paint',
      description: 'Flat, uniform paint finish',
      colors: [_paintWhite, _offWhite, _paintGrey, _duckEgg, _navy],
    ),
    WallFinishType.woodPanels: WallTypeSpec(
      label: 'Wood Panel',
      description: 'Vertical wood panel strips with deep seams',
      colors: [_oak, _walnut, _whitewashed],
    ),
    WallFinishType.brick: WallTypeSpec(
      label: 'Brick',
      description: 'Running-bond brick with dark mortar joints',
      colors: [_brickRed, _orangeBrick, _whitePainted],
    ),
  };

  // ─── Helpers (UI reads the catalog through these) ──────────────────────────

  static List<FinishColor> colorsForFloor(FloorFinishType type) =>
      floorTypes[type]!.colors;

  static List<FinishColor> colorsForWall(WallFinishType type) =>
      wallTypes[type]!.colors;

  static String floorLabel(FloorFinishType type) => floorTypes[type]!.label;

  static String floorDescription(FloorFinishType type) =>
      floorTypes[type]!.description;

  static String wallLabel(WallFinishType type) => wallTypes[type]!.label;

  static String wallDescription(WallFinishType type) =>
      wallTypes[type]!.description;

  static int defaultArgbForFloor(FloorFinishType type) =>
      colorsForFloor(type).first.argb;

  static int defaultArgbForWall(WallFinishType type) =>
      colorsForWall(type).first.argb;

  static String colorName(int argb, List<FinishColor> palette) {
    for (final c in palette) {
      if (c.argb == argb) return c.name;
    }
    return 'Custom';
  }
}

class FinishSelection {
  const FinishSelection({
    this.floorType = RoomFinishCatalog.defaultFloorType,
    this.floorColorArgb = RoomFinishCatalog.defaultFloorColorArgb,
    this.floorSizeM = RoomFinishCatalog.defaultFloorSizeM,
    this.wallType = RoomFinishCatalog.defaultWallType,
    this.wallColorArgb = RoomFinishCatalog.defaultWallColorArgb,
    Map<FloorFinishType, int>? floorColorsByType,
    Map<WallFinishType, int>? wallColorsByType,
  })  : _floorColorsByType = floorColorsByType,
        _wallColorsByType = wallColorsByType;

  final FloorFinishType floorType;
  final int floorColorArgb;
  final double floorSizeM;
  final WallFinishType wallType;
  final int wallColorArgb;

  final Map<FloorFinishType, int>? _floorColorsByType;
  final Map<WallFinishType, int>? _wallColorsByType;

  Map<FloorFinishType, int> get _floorMemory {
    return _floorColorsByType ?? const {};
  }

  Map<WallFinishType, int> get _wallMemory {
    return _wallColorsByType ?? const {};
  }

  FinishSelection selectFloorType(FloorFinishType type) {
    if (type == floorType) return this;
    final memory = Map<FloorFinishType, int>.of(_floorMemory)
      ..[floorType] = floorColorArgb;
    return FinishSelection(
      floorType: type,
      floorColorArgb: memory[type] ?? RoomFinishCatalog.defaultArgbForFloor(type),
      floorSizeM: floorSizeM,
      wallType: wallType,
      wallColorArgb: wallColorArgb,
      floorColorsByType: memory,
      wallColorsByType: _wallMemory,
    );
  }

  FinishSelection selectFloorColor(int colorArgb) {
    if (colorArgb == floorColorArgb) return this;
    final memory = Map<FloorFinishType, int>.of(_floorMemory)
      ..[floorType] = colorArgb;
    return FinishSelection(
      floorType: floorType,
      floorColorArgb: colorArgb,
      floorSizeM: floorSizeM,
      wallType: wallType,
      wallColorArgb: wallColorArgb,
      floorColorsByType: memory,
      wallColorsByType: _wallMemory,
    );
  }

  FinishSelection selectFloorSize(double sizeM) {
    if (sizeM == floorSizeM) return this;
    return FinishSelection(
      floorType: floorType,
      floorColorArgb: floorColorArgb,
      floorSizeM: sizeM,
      wallType: wallType,
      wallColorArgb: wallColorArgb,
      floorColorsByType: _floorMemory,
      wallColorsByType: _wallMemory,
    );
  }

  FinishSelection selectWallType(WallFinishType type) {
    if (type == wallType) return this;
    final memory = Map<WallFinishType, int>.of(_wallMemory)
      ..[wallType] = wallColorArgb;
    return FinishSelection(
      floorType: floorType,
      floorColorArgb: floorColorArgb,
      floorSizeM: floorSizeM,
      wallType: type,
      wallColorArgb: memory[type] ?? RoomFinishCatalog.defaultArgbForWall(type),
      floorColorsByType: _floorMemory,
      wallColorsByType: memory,
    );
  }

  FinishSelection selectWallColor(int colorArgb) {
    if (colorArgb == wallColorArgb) return this;
    final memory = Map<WallFinishType, int>.of(_wallMemory)
      ..[wallType] = colorArgb;
    return FinishSelection(
      floorType: floorType,
      floorColorArgb: floorColorArgb,
      floorSizeM: floorSizeM,
      wallType: wallType,
      wallColorArgb: colorArgb,
      floorColorsByType: _floorMemory,
      wallColorsByType: memory,
    );
  }

  FinishSelection copyWith({
    FloorFinishType? floorType,
    int? floorColorArgb,
    double? floorSizeM,
    WallFinishType? wallType,
    int? wallColorArgb,
  }) {
    return FinishSelection(
      floorType: floorType ?? this.floorType,
      floorColorArgb: floorColorArgb ?? this.floorColorArgb,
      floorSizeM: floorSizeM ?? this.floorSizeM,
      wallType: wallType ?? this.wallType,
      wallColorArgb: wallColorArgb ?? this.wallColorArgb,
      floorColorsByType: _floorMemory,
      wallColorsByType: _wallMemory,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FinishSelection &&
        other.floorType == floorType &&
        other.floorColorArgb == floorColorArgb &&
        other.floorSizeM == floorSizeM &&
        other.wallType == wallType &&
        other.wallColorArgb == wallColorArgb;
  }

  @override
  int get hashCode => Object.hash(
      floorType, floorColorArgb, floorSizeM, wallType, wallColorArgb);

  @override
  String toString() =>
      'FinishSelection(floor: ${floorType.name} #'
      '${floorColorArgb.toRadixString(16)} ${floorSizeM}m, wall: '
      '${wallType.name} #${wallColorArgb.toRadixString(16)})';
}
