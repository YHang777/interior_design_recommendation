import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../media/media_store.dart';
import 'verification_application_model.dart';

/// Raised when a verification submission cannot proceed — always carries a
/// message safe to surface to the supplier.
class VerificationException implements Exception {
  const VerificationException(this.message);

  final String message;

  @override
  String toString() => 'VerificationException: $message';
}

/// Supplier-side verification application pipeline.
///
/// Writes exactly two Firestore locations (full contract in
/// `verification_application_model.dart`), in this order:
///  1. upload every file to `verification/{uid}/{documentId}.{ext}`,
///  2. `set` `verification_applications/{uid}` with status `'pending'`,
///  3. update `users/{uid}` to `verificationStatus: 'pending'` +
///     `verificationSubmittedAt` (ISO-8601 UTC).
///
/// Storage note: Firebase Storage was removed from this project (Sep 2026 —
/// Cloud Storage for Firebase became Blaze-only), so the bytes go through
/// [MediaStore] (Cloudinary) at the same `verification/{uid}/{id}.{ext}`
/// path the contract specifies — the remote path doubles as the Cloudinary
/// public_id, which is what each document's `storagePath` records. The app
/// never reads the bytes back; only the admin console does.
class VerificationApplicationService {
  VerificationApplicationService({
    FirebaseFirestore? firestore,
    MediaStore? media,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _media = media ?? MediaStore.instance;

  final FirebaseFirestore _db;
  final MediaStore _media;

  static const String _applicationsCol = 'verification_applications';
  static const String _usersCol = 'users';
  static final Random _rng = Random();

  /// Submits (or re-submits after rejection) the supplier's application.
  ///
  /// The current status is deliberately NOT a caller parameter: the gate
  /// reads the live `users/{uid}` document, so a stale screen snapshot
  /// cannot sneak a second submission past `'pending'`. The state machine
  /// only ever moves towards `'pending'` — `'verified'` is written by the
  /// admin backend alone.
  Future<void> submitApplication({
    required String uid,
    required String email,
    String? businessName,
    required File icFront,
    required File icBack,
    List<File> supporting = const [],
  }) async {
    if (supporting.length > kMaxVerificationSupportingDocs) {
      throw VerificationException(
          'At most $kMaxVerificationSupportingDocs supporting documents '
          'are allowed.');
    }
    if (!_media.isConfigured) {
      throw const VerificationException(
          'Document upload is not configured on this build — set '
          'CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET (see '
          'LocalConfig).');
    }

    final userDoc = await _db.collection(_usersCol).doc(uid).get();
    if (!userDoc.exists) {
      throw const VerificationException(
          'Your profile could not be found — sign out and in again, then '
          'retry.');
    }
    final currentStatus =
        userDoc.data()?['verificationStatus']?.toString() ?? 'none';
    if (!maySubmitVerificationApplication(currentStatus)) {
      throw VerificationException(currentStatus == 'pending'
          ? 'Your application is already under review — an admin must '
              'review it before you can submit another.'
          : 'Your account is already verified.');
    }

    // Uploads happen before any Firestore write so a refused write never
    // leaves a half-created application document; a failure mid-way may
    // orphan earlier blobs, which Cloudinary tolerates.
    final documents = <VerificationDocument>[
      await _uploadDocument(
          uid: uid, file: icFront, kind: kVerificationDocIcFront),
      await _uploadDocument(
          uid: uid, file: icBack, kind: kVerificationDocIcBack),
      for (final file in supporting)
        await _uploadDocument(
            uid: uid, file: file, kind: kVerificationDocSupporting),
    ];

    final now = DateTime.now().toUtc();
    final application = VerificationApplication(
      uid: uid,
      email: email,
      businessName: businessName,
      status: 'pending',
      submittedAt: now,
      documents: documents,
    );

    try {
      // set() = create on first application, full replace on re-apply after
      // rejection. `firestore.rules` currently allows the owner to CREATE
      // only (updates are admin-backend-only) — if a re-apply is refused,
      // the permission-denied branch below surfaces it instead of failing
      // silently.
      await _db.collection(_applicationsCol).doc(uid).set(application.toJson());
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const VerificationException(
            'Firestore refused to store your application. If you are '
            're-applying after a rejection, your previous application may '
            'need to be cleared first — contact support.');
      }
      rethrow;
    }

    try {
      await _db.collection(_usersCol).doc(uid).update({
        'verificationStatus': 'pending',
        'verificationSubmittedAt': now.toIso8601String(),
        // The old rejection note belongs to the previous review round —
        // keeping it while pending would read as a live decision.
        'verificationReviewNote': null,
      });
    } on FirebaseException catch (e) {
      // The application document is already stored, and the UI resolves
      // status from its live stream — the supplier still lands in the
      // pending state even if this profile write fails.
      debugPrint('[verify] users/$uid status update failed: ${e.code}');
    }
  }

  /// Live view of the supplier's application — null until one exists.
  Stream<VerificationApplication?> watchMyApplication(String uid) {
    return _db
        .collection(_applicationsCol)
        .doc(uid)
        .snapshots()
        .map(_fromSnapshot);
  }

  /// One-shot read (for callers that need no stream).
  Future<VerificationApplication?> loadMyApplication(String uid) async {
    return _fromSnapshot(
        await _db.collection(_applicationsCol).doc(uid).get());
  }

  VerificationApplication? _fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return VerificationApplication.fromJson(data);
  }

  /// Validates and uploads one file, returning the contract record for it.
  Future<VerificationDocument> _uploadDocument({
    required String uid,
    required File file,
    required String kind,
  }) async {
    final label = _kindLabel(kind);
    if (!await file.exists()) {
      throw VerificationException(
          'The selected $label no longer exists — pick it again.');
    }
    final sizeBytes = await file.length();
    if (sizeBytes <= 0) {
      throw VerificationException(
          'The selected $label is empty — pick it again.');
    }
    if (sizeBytes > kMaxVerificationFileBytes) {
      throw VerificationException(
          'The selected $label is larger than '
          '${kMaxVerificationFileBytes ~/ (1024 * 1024)} MB — pick a '
          'smaller image.');
    }

    final id = _newDocumentId();
    final ext = _extensionFor(file.path);
    final storagePath = 'verification/$uid/$id.$ext';
    try {
      // remotePath doubles as the Cloudinary public_id, mirroring the
      // contract's Storage path so the admin console can resolve the file
      // from `storagePath` alone. The returned URL is deliberately unused:
      // the app only previews local picks, never downloads.
      await _media.uploadImageFile(file, storagePath);
    } on MediaStoreException catch (e) {
      throw VerificationException('Could not upload the $label: ${e.message}');
    } catch (e) {
      throw VerificationException('Could not upload the $label: $e');
    }

    return VerificationDocument(
      id: id,
      kind: kind,
      fileName: _fileNameFor(file.path),
      contentType: _contentTypeFor(ext),
      sizeBytes: sizeBytes,
      storagePath: storagePath,
      uploadedAt: DateTime.now().toUtc(),
    );
  }

  /// `{epochMillis}_{6 hex}` — unique, sortable, safe as a filename stem.
  static String _newDocumentId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final suffix = _rng.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '${millis}_$suffix';
  }

  static String _kindLabel(String kind) => switch (kind) {
        kVerificationDocIcFront => 'IC front image',
        kVerificationDocIcBack => 'IC back image',
        _ => 'supporting document',
      };

  /// Sane extension from the local path — image_picker writes `.jpg`/`.png`,
  /// but a share-intent path may lack one, so fall back rather than build a
  /// filename with a dangling dot.
  static String _extensionFor(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final dot = path.lastIndexOf('.');
    if (dot > slash && dot < path.length - 1) {
      final ext = path.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext)) return ext;
    }
    return 'jpg';
  }

  static String _fileNameFor(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final name = slash >= 0 ? path.substring(slash + 1) : path;
    return name.isEmpty ? 'image' : name;
  }

  static String _contentTypeFor(String ext) => switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        'gif' => 'image/gif',
        _ => 'application/octet-stream',
      };
}
