import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Append-only breadcrumb log for boot / auth.
///
/// Several OEM builds (Honor, Huawei) redact application logcat output, so
/// `debugPrint` never reaches `adb logcat` or `flutter run`. Writing to a
/// file in the app's documents directory is the only reliable way to see
/// where a startup or sign-in actually stalled:
///
///   adb shell run-as com.example.interior_design_recommendation \
///     cat app_flutter/boot_trace.log
class BootTrace {
  static Future<void> log(String message) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/boot_trace.log');
      await file.writeAsString(
        '[${DateTime.now().toIso8601String()}] $message\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Tracing must never take the app down.
    }
  }

  /// Clears the previous run's breadcrumbs so a reproduction is easy to read.
  static Future<void> start(String label) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/boot_trace.log');
      await file.writeAsString(
        '[${DateTime.now().toIso8601String()}] ===== $label =====\n',
      );
    } catch (_) {}
  }
}
