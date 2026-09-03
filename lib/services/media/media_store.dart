import 'dart:io';
import 'dart:typed_data';

import 'cloudinary_media_store.dart';
import 'supabase_media_store.dart';

/// Raised when a media upload fails in a way the caller should surface to
/// the user (unconfigured store, rejected upload, network failure, …).
class MediaStoreException implements Exception {
  const MediaStoreException(this.message);

  final String message;

  @override
  String toString() => 'MediaStoreException: $message';
}

/// Storage abstraction for the marketplace media pipeline (product photos
/// and published 3D GLB models).
///
/// Firebase Storage was swapped out in Sep 2026 — Cloud Storage for Firebase
/// no longer exists on the Spark plan. The default [instance] is a
/// [HybridMediaStore]: product photos go to Cloudinary (free tier, generous
/// 25 GB quota — its 10 MB per-file cap is irrelevant for photos) and GLB
/// models go to Supabase Storage (free tier, 50 MB per-file cap — a fit for
/// large textured Tripo output). The interface keeps every swap point
/// explicit so another backend (or Firebase Storage again, under Blaze) can
/// be dropped in behind one class.
abstract class MediaStore {
  /// Swap point — mirrors `FirebaseStorage.instance`'s spirit.
  static MediaStore instance = HybridMediaStore();

  /// Whether the store has enough configuration to attempt uploads.
  bool get isConfigured;

  /// Uploads a local image file (product photos) and returns its PUBLIC url.
  Future<String> uploadImageFile(
    File file,
    String remotePath, {
    void Function(double progress)? onProgress,
  });

  /// Uploads in-memory bytes (published GLB models) and returns its PUBLIC url.
  Future<String> uploadModelBytes(Uint8List bytes, String remotePath);

  /// Best-effort removal of a previously uploaded asset by url.
  Future<void> deleteByUrl(String url);
}

/// Routes [MediaStore] calls by asset kind — the two backends each do what
/// their free tier is best at:
///
///  - images → [CloudinaryMediaStore] (25 GB quota, 10 MB per-file cap);
///  - models → [SupabaseMediaStore] (50 MB per-file cap, 1 GB quota, real
///    deletes).
///
/// [deleteByUrl] is routed by URL shape (Cloudinary serves from
/// `res.cloudinary.com`, Supabase from `*.supabase.co`).
///
/// [isConfigured] reflects the IMAGE store only — the product form gates
/// photo uploads on it; the model path never consults it and each backend
/// throws its own specific configuration error instead.
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
