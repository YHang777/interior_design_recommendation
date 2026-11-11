import '../../../../models/room_design.dart';
import '../data/furniture_model_library.dart';

// What the AR viewer was opened with: the furniture bar to show, plus the
// plan whose room outline can be captured back out of the scan.
class ArViewerArgs {
  const ArViewerArgs({this.items, this.design, this.title});

  final List<ArFurnitureItem>? items;

  final RoomDesign? design;

  final String? title;
}
