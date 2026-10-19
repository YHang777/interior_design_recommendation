import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/utils/user_errors.dart';
import '../media/media_store.dart';
import 'verification_application_model.dart';

class VerificationException implements Exception, UserFacingException {
  const VerificationException(this.message, {String? userMessage})
      : _userMessage = userMessage;

  final String message;
  final String? _userMessage;

  @override
  String get userMessage =>
      _userMessage ?? 'Could not submit your application. Please try again.';

  @override
  String toString() => 'VerificationException: $message';
}

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
        'verificationReviewNote': null,
      });
    } on FirebaseException catch (e) {
      debugPrint('[verify] users/$uid status update failed: ${e.code}');
    }
  }

  Stream<VerificationApplication?> watchMyApplication(String uid) {
    return _db
        .collection(_applicationsCol)
        .doc(uid)
        .snapshots()
        .map(_fromSnapshot);
  }

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
      await _media.uploadImageFile(file, storagePath);
    } catch (e) {
      throw VerificationException(
        'Could not upload the $label: $e',
        userMessage: 'Could not upload the $label. Please try again.',
      );
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
