/// Data contract for supplier identity verification — shared verbatim with
/// the admin review console.
///
/// Two Firestore locations are involved:
///  - `users/{uid}` carries the derived fields the app already reads
///    (`verificationStatus`, `verificationSubmittedAt`, `verificationReviewNote`);
///  - `verification_applications/{uid}` (document id IS the supplier's uid)
///    holds this model plus the document inventory an admin reviews.
///
/// Pure Dart on purpose: no Flutter, no Firebase — the serialization and the
/// status state machine are unit-testable without either.
library;

/// Document kinds a supplier may attach. IC front/back are required;
/// `supporting` is optional (0–5).
const String kVerificationDocIcFront = 'ic_front';
const String kVerificationDocIcBack = 'ic_back';
const String kVerificationDocSupporting = 'supporting';

/// Per-file upload cap. Cloudinary's free tier rejects anything over 10 MB,
/// so failing in the app beats surfacing an opaque backend error later.
const int kMaxVerificationFileBytes = 10 * 1024 * 1024;

/// Maximum optional `supporting` documents per application (IC front and
/// back are additional and always required).
const int kMaxVerificationSupportingDocs = 5;

/// The verification status state machine — pure predicate over
/// `users/{uid}.verificationStatus`.
///
///  - `'none'`     → may submit (`none → pending` is the first application);
///  - `'rejected'` → may re-submit (`rejected → pending` is a re-application);
///  - `'pending'`  → read-only while the admin reviews (re-submit refused);
///  - `'verified'` → terminal (an admin approval is never undone by the app).
///
/// Only `'verified'` is ever granted by the admin backend — this function
/// never moves anything *towards* it.
bool maySubmitVerificationApplication(String currentStatus) =>
    currentStatus == 'none' || currentStatus == 'rejected';

/// Resolves the status the UI should render by merging the profile's stored
/// `verificationStatus` with the live `verification_applications/{uid}`
/// document.
///
/// The profile field is only refreshed when the session reloads, so an admin
/// approval would otherwise not appear until the next app start — the
/// application document is watched live and carries the same outcome. An
/// existing `'verified'` on the profile always wins (approval is terminal and
/// must never be downgraded by a lagging document); with no application on
/// file the profile status is the only truth (legacy accounts).
String resolveVerificationStatus(
  String userStatus,
  VerificationApplication? application,
) {
  if (application == null) return userStatus;
  if (userStatus == 'verified' || application.status == 'approved') {
    return 'verified';
  }
  if (application.status == 'rejected') return 'rejected';
  if (application.status == 'pending') return 'pending';
  return userStatus;
}

/// One uploaded file in a verification application — the exact shape stored
/// in `verification_applications/{uid}.documents[]`.
class VerificationDocument {
  const VerificationDocument({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.storagePath,
    this.uploadedAt,
  });

  /// Unique stem; also the storage filename (`{id}.{ext}`) and the generated
  /// document id inside the storage path.
  final String id;

  /// `'ic_front' | 'ic_back' | 'supporting'`.
  final String kind;

  final String fileName;
  final String contentType;
  final int sizeBytes;

  /// `verification/{uid}/{id}.{ext}` — how the admin console locates the
  /// bytes. The app never fetches this path itself (local previews only).
  final String storagePath;

  /// ISO-8601 UTC on write. Nullable only so documents written without the
  /// field still parse — submission always sets it.
  final DateTime? uploadedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        'storagePath': storagePath,
        'uploadedAt': uploadedAt?.toUtc().toIso8601String(),
      };

  factory VerificationDocument.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    return VerificationDocument(
      id: id,
      // A document without a kind was never written by this app; treat it as
      // supporting rather than guessing it is an IC page.
      kind: json['kind']?.toString() ?? kVerificationDocSupporting,
      fileName: json['fileName']?.toString() ?? id,
      contentType: json['contentType']?.toString() ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      storagePath: json['storagePath']?.toString() ?? '',
      uploadedAt: parseIsoDate(json['uploadedAt']),
    );
  }
}

/// The `verification_applications/{uid}` document (id IS the supplier uid).
class VerificationApplication {
  const VerificationApplication({
    required this.uid,
    required this.email,
    this.businessName,
    required this.status,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.reviewNote,
    this.documents = const [],
  });

  final String uid;
  final String email;
  final String? businessName;

  /// `'pending' | 'approved' | 'rejected'` — the admin's decision. Written by
  /// the client as `'pending'` only; the client never advances it further.
  final String status;

  /// ISO-8601 UTC on write; nullable on read for legacy documents.
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  /// The admin's Firebase uid.
  final String? reviewedBy;
  final String? reviewNote;

  final List<VerificationDocument> documents;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'businessName': businessName,
        'status': status,
        'submittedAt': submittedAt?.toUtc().toIso8601String(),
        'reviewedAt': reviewedAt?.toUtc().toIso8601String(),
        'reviewedBy': reviewedBy,
        'reviewNote': reviewNote,
        'documents': [for (final d in documents) d.toJson()],
      };

  factory VerificationApplication.fromJson(Map<String, dynamic> json) {
    return VerificationApplication(
      uid: json['uid']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      businessName: json['businessName']?.toString(),
      // Missing status defaults to 'pending': a document with no recorded
      // outcome is still awaiting review — defaulting to approved/rejected
      // would invent an admin decision.
      status: json['status']?.toString() ?? 'pending',
      submittedAt: parseIsoDate(json['submittedAt']),
      reviewedAt: parseIsoDate(json['reviewedAt']),
      reviewedBy: json['reviewedBy']?.toString(),
      reviewNote: json['reviewNote']?.toString(),
      documents: json['documents'] is List
          ? (json['documents'] as List)
              .whereType<Map<String, dynamic>>()
              .map(VerificationDocument.fromJson)
              .toList()
          : const [],
    );
  }
}

/// Parses the contract's ISO-8601 UTC strings, tolerating [DateTime] values
/// (local tests / other writers) and returning null when absent or malformed
/// rather than fabricating a timestamp.
DateTime? parseIsoDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
