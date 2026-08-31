// ============================================================
//  السلة والطلبات — مقابل commerce-service.js
//
//  المجاميع تُحسب داخل PostgreSQL فقط. الدالة
//  create_order_from_cart لا تقبل أي مبلغ من العميل، فالتلاعب
//  بالسعر ممتنع بنية النظام لا بسياسة قد يسهو عنها أحد.
//  لا تُضِف أبداً معامل سعر أو إجمالي إلى تلك الدالة.
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'auth_service.dart';

/// صنف في السلة بعد التطبيع.
class CartItem {
  CartItem({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.name,
    required this.price,
    required this.image,
    required this.factoryId,
    required this.factoryName,
  });

  final int id;
  final int productId;
  final int quantity;
  final String name;
  final double price;
  final String image;
  final int? factoryId;
  final String factoryName;

  double get lineTotal => price * quantity;

  CartItem copyWith({int? quantity}) => CartItem(
        id: id,
        productId: productId,
        quantity: quantity ?? this.quantity,
        name: name,
        price: price,
        image: image,
        factoryId: factoryId,
        factoryName: factoryName,
      );

  factory CartItem.fromRow(Map<String, dynamic> m) {
    final p = (m['products'] as Map?)?.cast<String, dynamic>() ?? {};
    final f = (p['factories'] as Map?)?.cast<String, dynamic>() ?? {};

    // تفضيل images[] على image: العمود القديم قد يحمل base64 مبتوراً
    // عند 2048 محرفاً (انظر save_factory_content في CLAUDE.md).
    String img = '';
    final images = p['images'];
    if (images is List) {
      for (final u in images) {
        if (u is String && u.startsWith('http')) {
          img = u;
          break;
        }
      }
    }
    if (img.isEmpty) {
      final single = p['image'];
      if (single is String && single.startsWith('http')) img = single;
    }

    return CartItem(
      id: (m['id'] as num).toInt(),
      productId: (m['product_id'] as num?)?.toInt() ?? 0,
      quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      name: (p['name'] as String?) ?? '',
      price: (p['price'] as num?)?.toDouble() ?? 0,
      image: img,
      factoryId: (p['factory_id'] as num?)?.toInt(),
      factoryName: (f['name'] as String?) ?? '',
    );
  }
}

class SFCommerce {
  SFCommerce._();

  static void _ready() {
    if (AuthService.instance.user == null) {
      throw Exception('يجب تسجيل الدخول للتسوق');
    }
  }

  static Future<List<CartItem>> loadCart() async {
    _ready();
    final cart = await sb.rpc('get_or_create_cart');
    final cartId = (cart is Map) ? cart['id'] : null;
    if (cartId == null) return [];

    final rows = await sb
        .from('cart_items')
        .select(
            'id, product_id, quantity, products(id, factory_id, name, price, image, images, factories(name))')
        .eq('cart_id', cartId)
        .order('created_at');

    return rows
        .map((e) => CartItem.fromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> addToCart(int productId, int quantity) async {
    _ready();
    await sb.rpc('add_to_cart', params: {
      'p_product_id': productId,
      'p_quantity': quantity < 1 ? 1 : quantity,
    });
  }

  static Future<void> setQuantity(int itemId, int quantity) async {
    _ready();
    if (quantity <= 0) return removeItem(itemId);
    if (quantity > 100000) throw Exception('الكمية كبيرة جداً');
    await sb
        .from('cart_items')
        .update({'quantity': quantity})
        .eq('id', itemId)
        .select();
  }

  static Future<void> removeItem(int itemId) async {
    _ready();
    await sb.from('cart_items').delete().eq('id', itemId).select();
  }

  /// إنشاء طلب — الخادم يحسب المبلغ ويرفض خلط مصنعين في طلب واحد.
  static Future<dynamic> createOrder(int factoryId) async {
    _ready();
    return sb.rpc('create_order_from_cart', params: {
      'p_factory_id': factoryId,
      'p_idempotency_key': _uuid(),
    });
  }

  static String _uuid() {
    // معرّف تكرار كافٍ لمنع ازدواج الطلب عند إعادة الإرسال.
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Object().hashCode.toRadixString(16);
    return '$now-$rand';
  }
}
