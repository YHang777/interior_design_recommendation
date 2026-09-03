import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../features/auth/data/models/app_user.dart' show UserRole;
import '../../models/product.dart';
import '../media/media_store.dart';
import 'generation_decider.dart';
import 'tripo_generator.dart';

/// Fire-and-forget entry point of the auto-3D pipeline. Call it with the
/// product returned by a create/update save, from failure-retry chips and
/// overflow-menu "Regenerate 3D" actions, and at boot for stuck products.
///
/// The WHOLE decision table lives in [decideGeneration] (pure — unit-tested
/// in generation_decision_test.dart). It guarantees, among other things:
///  - a healthy `ready` model is never re-kicked automatically;
///  - a persisted Tripo task id is always re-POLLED first — resuming a stuck
///    or transiently-failed generation never submits a second (paid) task;
///  - brand-new Tripo submissions are capped at `autoAttemptsCap` for
///    AUTOMATIC kicks, while explicit seller actions (`force`) may always
///    submit;
///  - forcing regeneration of a ready Tripo product never downgrades it to
///    the procedural model when the AI route is unavailable.
///
/// Returns the [GenerationDecision] so the UI can pick its snackbar
/// (fix: "Regenerate 3D" on a non-eligible ready Tripo product says the AI
/// model was kept instead of silently overwriting it).
///
/// All product-doc writes are PARTIAL `.update({'ar3d': …})` calls — never a
/// full-document overwrite. Terminal writes carry the FULL ar3d key set
/// (status/source/url/error/taskId/attempts/submittedAt/generatedAt).
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
    source: ar3d?.source ?? '',
    hasTaskId: ar3d?.hasTaskId ?? false,
    attempts: ar3d?.attempts ?? 0,
    dimsComplete: product.dimensions?.isComplete ?? false,
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
      firestore,
      mediaStore: mediaStore ?? MediaStore.instance,
    );
    if (decision.action == GenerationAction.submitNewTripo) {
      unawaited(_safe(() => generator.generateForProduct(product)));
    } else {
      unawaited(_safe(() => generator.pollExistingTask(product)));
    }
    return decision;
  }

  // ── Local writes (free; the deterministic generator materializes on
  //    demand in the AR viewer). Every map carries the full ar3d key set. ──
  final attempts = ar3d?.attempts ?? 0;
  switch (decision.action) {
    case GenerationAction.stampProcedural:
      _setAr3d(
        firestore,
        id,
        {
          'status': 'ready',
          'source': 'procedural',
          'url': '',
          'error': '',
          'taskId': '', // no AI task left to poll
          'attempts': attempts,
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
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
          'taskId': '', // nothing to re-poll
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
      break; // handled above / nothing to write
  }
  return decision;
}

/// Boot resume: generations interrupted by a crash or an app restart are
/// stuck as `ar3d.status == 'generating'` (the doc write happens before the
/// task runs). Re-kick up to 20 of the CURRENT SUPPLIER's products,
/// fire-and-forget.
///
/// Gated to suppliers (fix: boot resume must never trigger paid Tripo work
/// — or re-run a supplier's task stream — for a signed-in homeowner):
///  - requires an authenticated Firebase user whose `users/{uid}.role` is
///    `supplier`; homeowners and anonymous boots skip entirely;
///  - only that supplier's own products are resumed (`supplierId == uid`).
///
/// Decisions still run through [decideGeneration] (force: false): a doc with
/// a persisted task id is re-polled (free); one without (crash mid-submit)
/// is re-submitted at most until `autoAttemptsCap`, after which it is marked
/// failed with the cap message — resume can never bill a seller repeatedly.
/// Never throws.
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
