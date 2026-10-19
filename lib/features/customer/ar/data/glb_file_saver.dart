import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> saveGlbToAppDocuments(Uint8List bytes,
    {required String fileName}) async {
  final safeName = fileName
      .replaceAll(RegExp(r'[/\\]'), '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$safeName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
