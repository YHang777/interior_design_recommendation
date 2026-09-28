import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/utils/boot_trace.dart';
import 'firebase_options.dart';
import 'services/marketplace_repository.dart';
import 'services/model_generation/model_generation_trigger.dart';

/// Preference key gating the one-time marketplace catalogue seed. The flag
/// is written only after a SUCCESSFUL run so a failed attempt can retry on
/// the next launch.
const _seedDoneKey = 'marketplace_seed_v1';

/// How long to hold post-sign-in background work so it does not compete with
/// the login transition's own Firestore reads. See [_scheduleSeedAfterSignIn].
const _bootWorkDelay = Duration(seconds: 3);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BootTrace.start('main()');

  // Edge-to-edge display — status bar overlays page content.
  // Dark icons: pages are light and header-less. Full-bleed dark stages
  // (AR camera, scanner, photo heroes) opt back into light icons via
  // AnnotatedRegion<SystemUiOverlayStyle>.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await BootTrace.log('boot: before Firebase.initializeApp');
  // Firebase init is on the critical path to the first frame. If the
  // platform channel never returns (broken Play Services, blocked network),
  // the app would sit on the native splash forever — bound it so the UI
  // can still come up and report the failure.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
    await BootTrace.log('boot: Firebase.initializeApp OK');
  } catch (e) {
    await BootTrace.log('boot: Firebase.initializeApp FAILED: $e');
  }

  // The catalogue seed WRITES to Firestore, and the
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
    // Hold this background work until the sign-in transition has settled.
    // It fires on the same auth event as the login itself, and its write
    // burst plus `users/{uid}` and `products` reads race the login's own
    // profile read on the same Firestore client — landing exactly while the
    // splash is waiting on the network. Deferring costs nothing (this work is
    // idempotent and never urgent) and keeps the transition snappy.
    await Future<void>.delayed(_bootWorkDelay);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_seedDoneKey) ?? false)) {
        final repo = MarketplaceRepository(FirebaseFirestore.instance);
        await repo.seedMarketplaceIfEmpty();
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
