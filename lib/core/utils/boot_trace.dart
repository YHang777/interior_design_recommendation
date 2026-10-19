import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
    }
  }

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
