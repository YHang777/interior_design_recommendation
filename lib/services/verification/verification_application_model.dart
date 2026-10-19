library;

const String kVerificationDocIcFront = 'ic_front';
const String kVerificationDocIcBack = 'ic_back';
const String kVerificationDocSupporting = 'supporting';

const int kMaxVerificationFileBytes = 10 * 1024 * 1024;

const int kMaxVerificationSupportingDocs = 5;

bool maySubmitVerificationApplication(String currentStatus) =>
    currentStatus == 'none' || currentStatus == 'rejected';

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

  final String id;

  final String kind;

  final String fileName;
  final String contentType;
  final int sizeBytes;

  final String storagePath;

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
      kind: json['kind']?.toString() ?? kVerificationDocSupporting,
      fileName: json['fileName']?.toString() ?? id,
      contentType: json['contentType']?.toString() ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      storagePath: json['storagePath']?.toString() ?? '',
      uploadedAt: parseIsoDate(json['uploadedAt']),
    );
  }
}

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

  final String status;

  final DateTime? submittedAt;
  final DateTime? reviewedAt;

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

DateTime? parseIsoDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
