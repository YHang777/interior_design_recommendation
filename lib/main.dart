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

const _seedDoneKey = 'marketplace_seed_v1';

const _ratingBackfillKey = 'marketplace_rating_backfill_v1';

const _bootWorkDelay = Duration(seconds: 3);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BootTrace.start('main()');

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await BootTrace.log('boot: before Firebase.initializeApp');
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
    await BootTrace.log('boot: Firebase.initializeApp OK');
  } catch (e) {
    await BootTrace.log('boot: Firebase.initializeApp FAILED: $e');
  }

  _scheduleSeedAfterSignIn();

  runApp(
    const ProviderScope(
      child: InteriorDesignApp(),
    ),
  );
}

void _scheduleSeedAfterSignIn() {
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    await Future<void>.delayed(_bootWorkDelay);
    try {
      final prefs = await SharedPreferences.getInstance();
      final repo = MarketplaceRepository(FirebaseFirestore.instance);
      if (!(prefs.getBool(_seedDoneKey) ?? false)) {
        await repo.seedMarketplaceIfEmpty();
        await prefs.setBool(_seedDoneKey, true);
      }
      if (!(prefs.getBool(_ratingBackfillKey) ?? false)) {
        final repaired = await repo.backfillRatingsFromReviews();
        await prefs.setBool(_ratingBackfillKey, true);
        debugPrint('[bootstrap] rating backfill repaired $repaired products');
      }
    } catch (e) {
      debugPrint('[bootstrap] marketplace seed/backfill skipped: $e');
    }
    await resumeStuckGenerations();
  });
}
