import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'auth_service.dart';
import 'factory_service.dart';

class SFFavorite {
  const SFFavorite({required this.product, required this.factoryName});

  final SFProduct product;
  final String factoryName;

  static SFFavorite? fromRow(Map<String, dynamic> row) {
    final raw = row['products'];
    // المنتج المحذوف أو غير المتاح لا يتحول إلى بطاقة فارغة.
    if (raw is! Map) return null;
    final product = Map<String, dynamic>.from(raw);
    final factory = product['factories'];
    return SFFavorite(
      product: SFProduct(product),
      factoryName: factory is Map ? '${factory['name'] ?? ''}' : '',
    );
  }
}

class SFFavorites {
  SFFavorites._();

  static String get _uid {
    final id = AuthService.instance.user?.id;
    if (id == null) throw Exception('يجب تسجيل الدخول أولاً');
    return id;
  }

  static Future<List<SFFavorite>> load() async {
    final uid = _uid;
    final favorites = <SFFavorite>[];
    for (var start = 0; ; start += 500) {
      final rows = await sb
          .from('favorites')
          .select('id, product_id, products(*, factories(name))')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .order('id')
          .range(start, start + 499);
      for (final row in rows) {
        final item = SFFavorite.fromRow(row);
        if (item != null) favorites.add(item);
      }
      if (rows.length < 500) return favorites;
    }
  }

  static Future<Set<int>> loadIds() async {
    final uid = _uid;
    final ids = <int>{};
    for (var start = 0; ; start += 500) {
      final rows = await sb
          .from('favorites')
          .select('product_id')
          .eq('user_id', uid)
          .order('id')
          .range(start, start + 499);
      ids.addAll(rows.map((row) => (row['product_id'] as num).toInt()));
      if (rows.length < 500) return ids;
    }
  }

  static Future<bool> isFavorite(int productId) async {
    final row = await sb
        .from('favorites')
        .select('id')
        .eq('user_id', _uid)
        .eq('product_id', productId)
        .maybeSingle();
    return row != null;
  }

  static Future<void> add(int productId) async {
    try {
      await sb.from('favorites').insert({
        'user_id': _uid,
        'product_id': productId,
      });
    } on PostgrestException catch (error) {
      // تكرار الإضافة يعني أن الحالة المطلوبة محفوظة بالفعل.
      if (error.code != '23505') rethrow;
    }
  }

  static Future<void> remove(int productId) async {
    await sb
        .from('favorites')
        .delete()
        .eq('user_id', _uid)
        .eq('product_id', productId);
  }

  static Future<bool> toggle(int productId, {bool? isFavoriteNow}) async {
    final current = isFavoriteNow ?? await isFavorite(productId);
    if (current) {
      await remove(productId);
    } else {
      await add(productId);
    }
    return !current;
  }
}
