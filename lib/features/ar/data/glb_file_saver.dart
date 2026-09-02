import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Saves generated GLB bytes into the app's documents directory and returns
/// the absolute file path.
///
/// The AR plugin (`ar_flutter_plugin_2`) reads local models from the app's
/// documents folder via `NodeType.localGLB`, so files written here can be
/// placed directly in AR at true size.
///
/// Only the file name is used — any path separators in [fileName] are
/// stripped so the write always stays inside the documents directory.
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
