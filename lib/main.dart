import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'services/marketplace_repository.dart';
import 'services/model_generation/model_generation_trigger.dart';

/// Preference key gating the one-time marketplace seed/migration. The flag
/// is written only after a SUCCESSFUL run so a failed attempt can retry on
/// the next launch.
const _seedDoneKey = 'marketplace_seed_v1';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // The catalogue seed + legacy migration WRITE to Firestore, and the
  // security rules only allow writes for authenticated users. Fire-and-
  // forgetting at boot therefore always fails with PERMISSION_DENIED
  // (writes hit the sandbox before a session exists). Instead, subscribe to
  // auth state and run the seed once for the FIRST authenticated user.
  _scheduleSeedAfterSignIn();

  runApp(
    const ProviderScope(
      child: InteriorDesignApp(),
    ),
  );
}

/// Runs the one-time marketplace bootstrap as soon as a user signs in
/// (whether from a fresh login or a restored session). Each app instance
/// only ever triggers one attempt; the SharedPreferences flag keeps
/// re-logins (and relaunches after a success) from re-seeding. Failures are
/// logged only — boot never blocks on Firestore availability.
void _scheduleSeedAfterSignIn() {
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_seedDoneKey) ?? false)) {
        final repo = MarketplaceRepository(FirebaseFirestore.instance);
        await repo.seedMarketplaceIfEmpty();
        final migrated = await repo.migrateLegacyProducts();
        if (migrated > 0) {
          debugPrint('[bootstrap] legacy supplier backfill: '
              '$migrated products promoted to verified');
        }
        await prefs.setBool(_seedDoneKey, true);
      }
    } catch (e) {
      debugPrint('[bootstrap] marketplace seed skipped: $e');
    }
    // Resume 3D generations interrupted by a crash or app restart: products
    // stuck with ar3d.status == 'generating' are re-kicked (the state was
    // written before the Tripo task ran, so boot can always find them).
    // Runs on every authenticated start, never throws.
    await resumeStuckGenerations();
  });
}
