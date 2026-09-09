// التقييم متاح لكل حساب مسجّل؛ وسم المشتري الموثّق وحقوق الحذف يقرّرها الخادم.
import '../core/supabase_config.dart';
import 'auth_service.dart';

class SFProductRating {
  const SFProductRating({required this.average, required this.count});
  final double average;
  final int count;
}

class SFProductReview {
  SFProductReview(this.raw);
  final Map<String, dynamic> raw;
  int get id => (raw['id'] as num).toInt();
  int get rating => (raw['rating'] as num?)?.toInt() ?? 0;
  String get body => '${raw['body'] ?? ''}';
  String get authorName => '${raw['author_name'] ?? ''}';
  String get authorImage => '${raw['author_image'] ?? ''}';
  bool get isMine => raw['is_mine'] == true;
  bool get isVerified => raw['is_verified'] == true;
  DateTime? get createdAt =>
      DateTime.tryParse('${raw['created_at']}')?.toLocal();
}

class SFReviewStatus {
  const SFReviewStatus({this.canReview = false, this.hasReview = false});
  final bool canReview;
  final bool hasReview;
}

class SFFactorySummary {
  const SFFactorySummary({
    required this.approved,
    required this.products,
    required this.city,
  });
  final bool approved;
  final int products;
  final String city;
}

class SFReviews {
  SFReviews._();

  static Future<Map<int, SFProductRating>> loadRatings(
    List<int> productIds,
  ) async {
    final ids = productIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await sb.rpc(
      'get_product_ratings',
      params: {'p_product_ids': ids},
    );
    return {
      for (final row in rows as List)
        (row['product_id'] as num).toInt(): SFProductRating(
          average: (row['rating_avg'] as num?)?.toDouble() ?? 0,
          count: (row['rating_count'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  static Future<List<SFProductReview>> loadReviews(
    int productId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await sb.rpc(
      'get_product_reviews',
      params: {
        'p_product_id': productId,
        'p_limit': limit.clamp(1, 100),
        'p_offset': offset < 0 ? 0 : offset,
      },
    );
    return (rows as List)
        .map((row) => SFProductReview(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  static Future<SFReviewStatus> myStatus(int productId) async {
    if (!AuthService.instance.isSignedIn) return const SFReviewStatus();
    final rows = await sb.rpc(
      'can_review_product',
      params: {'p_product_id': productId},
    );
    if ((rows as List).isEmpty) return const SFReviewStatus();
    return SFReviewStatus(
      canReview: rows.first['can_review'] == true,
      hasReview: rows.first['has_review'] == true,
    );
  }

  static Future<SFProductReview?> myReview(int productId) async {
    final uid = AuthService.instance.user?.id;
    if (uid == null) return null;
    final row = await sb
        .from('product_reviews')
        .select('id,rating,body,created_at')
        .eq('product_id', productId)
        .eq('author_id', uid)
        .maybeSingle();
    return row == null ? null : SFProductReview({...row, 'is_mine': true});
  }

  static Future<void> submitReview(
    int productId,
    int rating,
    String body,
  ) async {
    final uid = AuthService.instance.user?.id;
    if (uid == null) throw Exception('يرجى تسجيل الدخول أولاً');
    if (rating < 1 || rating > 5) throw Exception('اختر تقييماً من 1 إلى 5.');
    final text = body.trim();
    final rows = await sb.from('product_reviews').upsert({
      'product_id': productId,
      'author_id': uid,
      'rating': rating,
      'body': text.length > 2000 ? text.substring(0, 2000) : text,
    }, onConflict: 'product_id,author_id').select();
    if (rows.isEmpty) {
      throw Exception('تعذّر حفظ المراجعة. حدّث الصفحة وحاول مرّة أخرى.');
    }
  }

  static Future<bool> deleteReview(int reviewId) async {
    if (!AuthService.instance.isSignedIn) {
      throw Exception('يرجى تسجيل الدخول أولاً');
    }
    final rows = await sb
        .from('product_reviews')
        .delete()
        .eq('id', reviewId)
        .select('id');
    return rows.isNotEmpty;
  }

  static Future<Map<int, int>> loadBreakdown(int productId) async {
    final rows = await sb.rpc(
      'get_rating_breakdown',
      params: {'p_product_id': productId},
    );
    return {
      for (var star = 1; star <= 5; star++) star: 0,
      for (final row in rows as List)
        (row['rating'] as num).toInt(): (row['cnt'] as num).toInt(),
    };
  }

  static Future<SFFactorySummary?> loadFactorySummary(int factoryId) async {
    final rows = await sb.rpc(
      'get_factory_summary',
      params: {'p_factory_id': factoryId},
    );
    if ((rows as List).isEmpty) return null;
    final row = rows.first;
    return SFFactorySummary(
      approved: row['is_approved'] == true,
      products: (row['product_count'] as num?)?.toInt() ?? 0,
      city: '${row['city'] ?? ''}',
    );
  }
}
