import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../features/auth/data/models/app_user.dart' show UserRole;
import '../../features/customer/ar/data/glb_rescaler.dart'
    show hasAnySellerDimension;
import '../../models/product.dart';
import '../media/media_store.dart';
import 'generation_decider.dart';
import 'tripo_generator.dart';

GenerationDecision kickOffProduct3DGeneration(
  Product product, {
  bool force = false,
  FirebaseFirestore? db,
  MediaStore? mediaStore,
}) {
  final id = product.id.trim();
  if (id.isEmpty) {
    return const GenerationDecision(GenerationAction.none);
  }
  final ar3d = product.ar3d;
  final decision = decideGeneration(
    status: ar3d?.status ?? 'none',
    hasTaskId: ar3d?.hasTaskId ?? false,
    attempts: ar3d?.attempts ?? 0,
    hasDimensions: hasAnySellerDimension(product.dimensions),
    hasNetworkImage: product.hasNetworkImage,
    tripoConfigured: Tripo3DGenerator.isConfigured,
    force: force,
  );
  debugPrint('[model-3d] kick-off "${product.name}" ($id): '
      '${decision.action}${decision.message.isEmpty ? '' : ' — ${decision.message}'}');

  final firestore = db ?? FirebaseFirestore.instance;

  // ── Network runs are guarded per-product (one in flight per process). ──
  if (decision.action == GenerationAction.submitNewTripo ||
      decision.action == GenerationAction.pollExistingTask) {
    if (Tripo3DGenerator.isRunning(id)) {
      return const GenerationDecision(
        GenerationAction.none,
        message: '3D generation is already running for this product.',
      );
    }
    final generator = Tripo3DGenerator(
      FirestoreAr3dStore(firestore),
      mediaStore: mediaStore ?? MediaStore.instance,
    );
    if (decision.action == GenerationAction.submitNewTripo) {
      unawaited(_safe(() => generator.generateForProduct(product)));
    } else {
      unawaited(_safe(() => generator.pollExistingTask(product)));
    }
    return decision;
  }

  // ── Local writes (free). Every map carries the full ar3d key set. ──────
  final attempts = ar3d?.attempts ?? 0;
  switch (decision.action) {
    case GenerationAction.stampProcedural:
      debugPrint('[model-3d] BUG: stampProcedural requested for $id — '
          'the procedural model source no longer exists; ignoring.');
      break;
    case GenerationAction.markFailed:
      _setAr3d(
        firestore,
        id,
        {
          'status': 'failed',
          'source': ar3d?.source ?? '',
          'url': '',
          'error': decision.message,
          'taskId': '',
          'attempts': attempts,
        },
      );
      break;
    case GenerationAction.markNoModel:
      _setAr3d(
        firestore,
        id,
        {
          'status': 'none',
          'source': '',
          'url': '',
          'error': '',
          'taskId': '',
          'attempts': attempts,
        },
      );
      break;
    case GenerationAction.none:
    case GenerationAction.submitNewTripo:
    case GenerationAction.pollExistingTask:
      break;
  }
  return decision;
}

Future<void> resumeStuckGenerations({
  FirebaseFirestore? db,
  MediaStore? mediaStore,
}) async {
  final firestore = db ?? FirebaseFirestore.instance;
  try {
    // ── Supplier-role gate ──────────────────────────────────────────────
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[model-3d] resume skipped — no signed-in user');
      return;
    }
    final userDoc = await firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists) {
      debugPrint('[model-3d] resume skipped — no users/${user.uid} doc');
      return;
    }
    final role =
        UserRole.fromString(userDoc.data()?['role']?.toString() ?? '');
    if (role != UserRole.supplier) {
      debugPrint('[model-3d] resume skipped — ${user.uid} is not a supplier');
      return;
    }

    final snap = await firestore
        .collection('products')
        .where('ar3d.status', isEqualTo: 'generating')
        .where('supplierId', isEqualTo: user.uid)
        .limit(20)
        .get();
    if (snap.docs.isEmpty) return;
    debugPrint('[model-3d] resuming ${snap.docs.length} stuck generation(s) '
        'of supplier ${user.uid}');
    for (final doc in snap.docs) {
      try {
        final product = Product.fromJson(doc.data());
        kickOffProduct3DGeneration(product, db: firestore, mediaStore: mediaStore);
      } catch (e) {
        debugPrint('[model-3d] resume kick-off failed for '
            '${doc.id}: $e');
      }
    }
  } catch (e) {
    debugPrint('[model-3d] resume query failed: $e');
  }
}

Future<void> _safe(Future<void> Function() run) async {
  try {
    await run();
  } catch (e) {
    debugPrint('[model-3d] kick-off failed: $e');
  }
}

void _setAr3d(
    FirebaseFirestore db, String productId, Map<String, dynamic> ar3d) {
  unawaited(_safe(() =>
      db.collection('products').doc(productId).update({'ar3d': ar3d})));
}
