/// A product review left by a buyer. Stored in the
/// `products/{id}/reviews` subcollection.
class Review {
  final String id;
  final String userId;
  final String userName;
  final int rating;
  final String comment;
  final DateTime createdAt;

  /// The order this review belongs to. Review documents written through the
  /// buyer order flow use the ORDER id as the review doc id, making
  /// "has this order already reviewed product X?" a cheap doc read
  /// (`products/{productId}/reviews/{orderId}`).
  final String orderId;

  const Review({
    required this.id,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.orderId = '',
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? 'Anonymous',
      rating: (json['rating'] as num?)?.round() ?? 5,
      comment: json['comment']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? _parseReviewDate(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      orderId: json['orderId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'rating': rating,
        'comment': comment,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'orderId': orderId,
      };
}

/// Parses a date that may be an ISO-8601 string or a Firestore Timestamp.
DateTime? _parseReviewDate(dynamic value) {
  if (value is DateTime) return value;
  try {
    final toDate = value.toDate;
    if (toDate is Function) {
      final parsed = value.toDate();
      if (parsed is DateTime) return parsed;
    }
  } catch (_) {}
  return DateTime.tryParse(value.toString());
}
