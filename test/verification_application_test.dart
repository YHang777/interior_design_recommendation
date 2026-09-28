// Tests for the supplier verification data contract and status state
// machine (the pure logic behind the admin verification application work).
//
// Pure Dart — no widgets, no Firebase, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/services/verification/verification_application_model.dart';

void main() {
  final uploadedAt = DateTime.utc(2026, 9, 28, 10, 30, 15);
  final submittedAt = DateTime.utc(2026, 9, 28, 12, 0, 0);

  VerificationDocument buildDocument() => VerificationDocument(
        id: '1769000000000_abc123',
        kind: kVerificationDocIcFront,
        fileName: 'ic_front.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 123456,
        storagePath: 'verification/u1/1769000000000_abc123.jpg',
        uploadedAt: uploadedAt,
      );

  VerificationApplication buildApplication() => VerificationApplication(
        uid: 'u1',
        email: 'supplier@example.com',
        businessName: 'Kedai Perabot',
        status: 'pending',
        submittedAt: submittedAt,
        documents: [buildDocument()],
      );

  // ── VerificationDocument ───────────────────────────────────────────────

  group('VerificationDocument serialization', () {
    test('toJson emits exactly the contract key set', () {
      expect(
        buildDocument().toJson().keys.toSet(),
        {
          'id',
          'kind',
          'fileName',
          'contentType',
          'sizeBytes',
          'storagePath',
          'uploadedAt',
        },
      );
    });

    test('dates serialize as ISO-8601 UTC strings and round-trip', () {
      final json = buildDocument().toJson();
      expect(json['uploadedAt'], isA<String>());
      expect(json['uploadedAt'], '2026-09-28T10:30:15.000Z');
      expect(DateTime.parse(json['uploadedAt'] as String).isUtc, isTrue);

      final parsed = VerificationDocument.fromJson(json);
      expect(parsed.uploadedAt, uploadedAt);
      expect(parsed.id, '1769000000000_abc123');
      expect(parsed.storagePath, 'verification/u1/1769000000000_abc123.jpg');
      expect(parsed.sizeBytes, 123456);
      expect(parsed.kind, kVerificationDocIcFront);
      expect(parsed.contentType, 'image/jpeg');
      expect(parsed.fileName, 'ic_front.jpg');
    });

    test('fromJson tolerates a legacy document missing every field', () {
      final legacy = VerificationDocument.fromJson(const {});
      expect(legacy.id, '');
      // Never guess that an unlabelled attachment is an IC page.
      expect(legacy.kind, kVerificationDocSupporting);
      expect(legacy.fileName, '');
      expect(legacy.contentType, '');
      expect(legacy.sizeBytes, 0);
      expect(legacy.storagePath, '');
      expect(legacy.uploadedAt, isNull);
    });

    test('fromJson survives an unparseable date instead of throwing', () {
      final doc = VerificationDocument.fromJson(const {
        'id': 'x',
        'uploadedAt': 'not-a-timestamp',
      });
      expect(doc.uploadedAt, isNull);
    });
  });

  // ── VerificationApplication ────────────────────────────────────────────

  group('VerificationApplication serialization', () {
    test('toJson emits exactly the contract key set', () {
      expect(
        buildApplication().toJson().keys.toSet(),
        {
          'uid',
          'email',
          'businessName',
          'status',
          'submittedAt',
          'reviewedAt',
          'reviewedBy',
          'reviewNote',
          'documents',
        },
      );
    });

    test('dates serialize as ISO-8601 UTC and documents round-trip', () {
      final json = buildApplication().toJson();
      expect(json['submittedAt'], '2026-09-28T12:00:00.000Z');
      expect(json['reviewedAt'], isNull);
      expect(json['reviewedBy'], isNull);
      expect(json['reviewNote'], isNull);
      expect(json['documents'], isA<List<dynamic>>());
      expect((json['documents'] as List).length, 1);

      final parsed = VerificationApplication.fromJson(json);
      expect(parsed.uid, 'u1');
      expect(parsed.email, 'supplier@example.com');
      expect(parsed.businessName, 'Kedai Perabot');
      expect(parsed.status, 'pending');
      expect(parsed.submittedAt, submittedAt);
      expect(parsed.documents.single.storagePath,
          'verification/u1/1769000000000_abc123.jpg');
      expect(parsed.documents.single.uploadedAt, uploadedAt);
    });

    test('fromJson defaults for a legacy document missing the fields', () {
      final legacy = VerificationApplication.fromJson(const {'uid': 'u1'});
      expect(legacy.uid, 'u1');
      expect(legacy.email, '');
      expect(legacy.businessName, isNull);
      // No recorded outcome means still awaiting review — never invent an
      // approval (or a rejection) for it.
      expect(legacy.status, 'pending');
      expect(legacy.submittedAt, isNull);
      expect(legacy.reviewedAt, isNull);
      expect(legacy.reviewedBy, isNull);
      expect(legacy.reviewNote, isNull);
      expect(legacy.documents, isEmpty);
    });

    test('review outcome fields survive an admin-written document', () {
      final reviewed = VerificationApplication.fromJson({
        'uid': 'u1',
        'email': 'supplier@example.com',
        'status': 'rejected',
        'submittedAt': submittedAt.toIso8601String(),
        'reviewedAt': uploadedAt.toIso8601String(),
        'reviewedBy': 'admin-uid',
        'reviewNote': 'IC photo is blurry',
        'documents': [buildDocument().toJson()],
      });
      expect(reviewed.status, 'rejected');
      expect(reviewed.reviewedBy, 'admin-uid');
      expect(reviewed.reviewNote, 'IC photo is blurry');
      expect(reviewed.reviewedAt, uploadedAt);
      expect(reviewed.documents, hasLength(1));
    });
  });

  // ── State machine ──────────────────────────────────────────────────────

  group('verification status state machine', () {
    test('none → pending is allowed (first application)', () {
      expect(maySubmitVerificationApplication('none'), isTrue);
    });

    test('rejected → pending is allowed (re-application)', () {
      expect(maySubmitVerificationApplication('rejected'), isTrue);
    });

    test('pending is read-only — re-submit refused', () {
      expect(maySubmitVerificationApplication('pending'), isFalse);
    });

    test('verified is terminal — no re-apply', () {
      expect(maySubmitVerificationApplication('verified'), isFalse);
    });
  });

  // ── AppUser defaults ───────────────────────────────────────────────────

  group('AppUser verification defaults', () {
    AppUser userWith({Map<String, dynamic> data = const {}}) =>
        AppUser.fromFirestore(uid: 'u1', email: 's@example.com', data: {
          'role': 'supplier',
          ...data,
        });

    test('every new account starts at none and may apply', () {
      final user = userWith();
      expect(user.verificationStatus, 'none');
      expect(user.isVerified, isFalse);
      expect(user.canSubmitVerification, isTrue);
    });

    test('a stored status is honoured — legacy verified accounts keep it',
        () {
      final legacy = userWith(data: {'verificationStatus': 'verified'});
      expect(legacy.verificationStatus, 'verified');
      expect(legacy.isVerified, isTrue);
      expect(legacy.canSubmitVerification, isFalse);
    });

    test('canSubmitVerification for each status', () {
      expect(userWith(data: {'verificationStatus': 'none'}).canSubmitVerification,
          isTrue);
      expect(
          userWith(data: {'verificationStatus': 'rejected'})
              .canSubmitVerification,
          isTrue);
      expect(
          userWith(data: {'verificationStatus': 'pending'})
              .canSubmitVerification,
          isFalse);
      expect(
          userWith(data: {'verificationStatus': 'verified'})
              .canSubmitVerification,
          isFalse);
    });
  });

  // ── Live status resolution ─────────────────────────────────────────────

  group('resolveVerificationStatus', () {
    VerificationApplication app(String status) => VerificationApplication(
        uid: 'u1', email: 's@example.com', status: status);

    test('no application on file → profile status (legacy accounts)', () {
      expect(resolveVerificationStatus('verified', null), 'verified');
      expect(resolveVerificationStatus('none', null), 'none');
    });

    test('a fresh submission shows pending before the profile catches up',
        () {
      expect(resolveVerificationStatus('none', app('pending')), 'pending');
      expect(
          resolveVerificationStatus('rejected', app('pending')), 'pending');
    });

    test('admin approval appears live from the application stream', () {
      expect(resolveVerificationStatus('pending', app('approved')),
          'verified');
    });

    test('admin rejection appears live from the application stream', () {
      expect(resolveVerificationStatus('pending', app('rejected')),
          'rejected');
    });

    test('a stored approval is never downgraded by a lagging document', () {
      expect(resolveVerificationStatus('verified', app('pending')),
          'verified');
    });
  });
}
