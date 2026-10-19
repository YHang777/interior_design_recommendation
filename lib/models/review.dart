class Review {
  final String id;
  final String userId;
  final String userName;
  final int rating;
  final String comment;
  final DateTime createdAt;

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

double rollingRating({
  required int ratingCount,
  required double rating,
  required int added,
}) {
  final count = ratingCount + 1;
  final total = rating * ratingCount + added;
  return (total / count * 10).roundToDouble() / 10;
}

({double rating, int ratingCount}) aggregateForRatings(List<int> stars) {
  if (stars.isEmpty) return (rating: 0.0, ratingCount: 0);
  final total = stars.fold<int>(0, (sum, star) => sum + star);
  return (
    rating: (total / stars.length * 10).roundToDouble() / 10,
    ratingCount: stars.length,
  );
}

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
