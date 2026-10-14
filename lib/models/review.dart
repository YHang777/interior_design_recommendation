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

/// The product-level rating after ONE more review of [added] stars lands on
/// a listing currently showing [rating] over [ratingCount] reviews.
///
/// Sum-based over the stored (rating × ratingCount) baseline — never
/// re-averages an already-rounded average — then rounded to one decimal.
/// This is the exact arithmetic `MarketplaceRepository.addReview` commits
/// inside its transaction, kept pure so tests can pin it without Firestore.
/// A virgin listing (0.0 / 0) simply becomes the new review's rating.
double rollingRating({
  required int ratingCount,
  required double rating,
  required int added,
}) {
  final count = ratingCount + 1;
  final total = rating * ratingCount + added;
  return (total / count * 10).roundToDouble() / 10;
}

/// The (rating, ratingCount) a product document SHOULD show given [stars] —
/// the star values of every review that actually exists for it.
///
/// No reviews resolves to 0.0 / 0: the honest answer, and the repair for
/// catalogues seeded with fabricated 4.5/12 defaults (which would otherwise
/// poison every rolling aggregate computed on top of them).
({double rating, int ratingCount}) aggregateForRatings(List<int> stars) {
  if (stars.isEmpty) return (rating: 0.0, ratingCount: 0);
  final total = stars.fold<int>(0, (sum, star) => sum + star);
  return (
    rating: (total / stars.length * 10).roundToDouble() / 10,
    ratingCount: stars.length,
  );
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
