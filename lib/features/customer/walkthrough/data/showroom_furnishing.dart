import '../../../../models/product.dart';
import '../../../../models/room_design.dart';
import '../../homeowner/presentation/providers/design_providers.dart'
    show iconNameForProduct, productHasReady3d, productModelUrl;

// Showroom pieces render the best model available, in order: a live
// marketplace product of the same type with a ready GLB, the room's bundled
// variant (modelUrl 'assets/models/…'), then the catalog model for the type.
// The curated footprint stays — the layout was designed around it — while
// the product's name, photo, height and GLB ride along.
RoomDesign furnishWithMarketplace(RoomDesign design, List<Product> market) {
  final ready = [
    for (final p in market)
      if (productHasReady3d(p)) p,
  ];
  if (ready.isEmpty) return design;
  var changed = false;
  final furniture = [
    for (final f in design.furniture)
      () {
        Product? match;
        for (final p in ready) {
          if (iconNameForProduct(p) == f.iconName) {
            match = p;
            break;
          }
        }
        if (match == null) return f;
        changed = true;
        final h = match.dimensions!.heightM * 100;
        return f.copyWith(
          name: match.name,
          productId: match.id,
          modelUrl: productModelUrl(match),
          heightCm: h > 0 ? h : null,
          imageUrl: match.image.isEmpty ? null : match.image,
        );
      }(),
  ];
  return changed ? design.copyWith(furniture: furniture) : design;
}
