import 'dart:io';
import 'dart:typed_data';

import 'cloudinary_media_store.dart';
import 'supabase_media_store.dart';

class MediaStoreException implements Exception {
  const MediaStoreException(this.message);

  final String message;

  @override
  String toString() => 'MediaStoreException: $message';
}

abstract class MediaStore {
  static MediaStore instance = HybridMediaStore();

  bool get isConfigured;

  Future<String> uploadImageFile(
    File file,
    String remotePath, {
    void Function(double progress)? onProgress,
  });

  Future<String> uploadModelBytes(Uint8List bytes, String remotePath);

  Future<void> deleteByUrl(String url);
}

class HybridMediaStore implements MediaStore {
  HybridMediaStore({MediaStore? images, MediaStore? models})
      : _images = images ?? CloudinaryMediaStore(),
        _models = models ?? SupabaseMediaStore();

  final MediaStore _images;
  final MediaStore _models;

  @override
  bool get isConfigured => _images.isConfigured;

  @override
  Future<String> uploadImageFile(
    File file,
    String remotePath, {
    void Function(double progress)? onProgress,
  }) {
    return _images.uploadImageFile(file, remotePath, onProgress: onProgress);
  }

  @override
  Future<String> uploadModelBytes(Uint8List bytes, String remotePath) {
    return _models.uploadModelBytes(bytes, remotePath);
  }

  @override
  Future<void> deleteByUrl(String url) async {
    if (url.contains('supabase.co')) {
      await _models.deleteByUrl(url);
      return;
    }
    await _images.deleteByUrl(url);
  }
}
