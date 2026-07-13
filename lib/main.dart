import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialization is deferred until credentials are available.
  // For now, MockAuthRepository is used via authRepositoryProvider.
  // When Firebase is ready:
  //   1. Add google-services.json to android/app/
  //   2. Call Firebase.initializeApp() here
  //   3. Switch authRepositoryProvider to AuthRepositoryImpl

  runApp(
    const ProviderScope(
      child: InteriorDesignApp(),
    ),
  );
}
