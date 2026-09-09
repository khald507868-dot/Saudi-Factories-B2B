// ============================================================
//  المصانع والمنتجات والمنشورات
//
//  الحفظ يمرّ عبر الدالة save_factory_content: تتحقّق من
//  الملكية داخل الخادم، وتقصّ كل قيمة عند 2048 محرفاً.
//  ولذلك تُرسل روابط التخزين فقط — لا base64.
//
//  ملاحظة عن القراءة: RLS هي من تُصفّي القائمة، فلا تُضِف
//  eq('status','approved') — ذلك يُخفي مصنع المالك المعلّق عنه.
// ============================================================

import '../core/supabase_config.dart';
import '../core/pricing.dart';
import 'auth_service.dart';

/// حقول المصنع التي تقرأها الشاشات.
/// أي شاشة تحتاج عموداً جديداً تضيفه هنا — عمود مفقود في
/// قائمة select يُفشل الاستعلام كلّه بالرمز 42703.
const String kFactorySelect = '''
id, owner_id, status, rejection_reason, name, about, cover, logo,
commercial_register, industrial_license, region_id, website, industry,
company_size, address_city, address_district, address_short,
address_building, address_secondary, address_postal, address_street,
created_at, updated_at
''';

class SFFactory {
  SFFactory(this.raw);

  final Map<String, dynamic> raw;

  int get id => (raw['id'] as num).toInt();
  String? get ownerId => raw['owner_id'] as String?;
  String get status => (raw['status'] as String?) ?? 'pending';
  String get name => (raw['name'] as String?) ?? '';
  String get about => (raw['about'] as String?) ?? '';
  String get cover => _http(raw['cover']);
  String get logo => _http(raw['logo']);
  String get industry => (raw['industry'] as String?) ?? '';
  String get regionId => (raw['region_id'] as String?) ?? '';
  String get website => (raw['website'] as String?) ?? '';
  Uri? get websiteUri => normalizedWebsite(website);
  String get companySize => (raw['company_size'] as String?) ?? '';
  String get rejectionReason => (raw['rejection_reason'] as String?) ?? '';
  String? get updatedAt => raw['updated_at'] as String?;

  String get city => (raw['address_city'] as String?) ?? '';
  String get district => (raw['address_district'] as String?) ?? '';

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';

  /// هل يملك المستخدم الحالي هذا المصنع؟ هذا هو القرار الوحيد
  /// الموثوق لإظهار واجهة التحرير — لا sf_account_type.
  bool get isMine {
    final uid = AuthService.instance.user?.id;
    return uid != null && ownerId == uid;
  }

  /// القيم القديمة قد تحمل base64 مبتوراً؛ لا نعرض إلا الروابط.
  static String _http(dynamic v) {
    return safeMediaUrl(v);
  }
}

class SFProduct {
  SFProduct(this.raw);

  final Map<String, dynamic> raw;

  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  int get factoryId => (raw['factory_id'] as num?)?.toInt() ?? 0;
  String get name => (raw['name'] as String?) ?? '';
  double get price => (raw['price'] as num?)?.toDouble() ?? 0;
  String get description => (raw['description'] as String?) ?? '';
  String get material => (raw['material'] as String?) ?? '';
  String get sizes => (raw['sizes'] as String?) ?? '';
  String get colors => (raw['colors'] as String?) ?? '';
  int? get moq => (raw['moq'] as num?)?.toInt();
  List<SFPriceTier> get tiers => SFPriceTier.parseList(raw['tiers']);
  double unitPrice(int quantity) =>
      SFPriceCalculation.unitPrice(price, tiers, quantity);
  double get minPrice => tiers.isEmpty
      ? price
      : tiers.map((tier) => tier.price).reduce((a, b) => a < b ? a : b);
  double get maxPrice => tiers.isEmpty
      ? price
      : tiers.map((tier) => tier.price).reduce((a, b) => a > b ? a : b);
  List<String> get images {
    final gallery = raw['images'];
    final urls = <String>[];
    if (gallery is List) {
      for (final value in gallery) {
        final url = safeMediaUrl(value);
        if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
      }
    }
    if (urls.isEmpty) {
      final single = safeMediaUrl(raw['image']);
      if (single.isNotEmpty) urls.add(single);
    }
    return urls.take(5).toList();
  }

  /// يُفضّل images[] على image — انظر تعليق CartItem.
  String get image => images.isEmpty ? '' : images.first;
}

class SFPost {
  SFPost(this.raw);

  final Map<String, dynamic> raw;

  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  String get body => (raw['body'] as String?) ?? '';
  String get image => safeMediaUrl(raw['image']);
  String get video => safeMediaUrl(raw['video']);

  DateTime get createdAt =>
      DateTime.tryParse('${raw['created_at']}')?.toLocal() ?? DateTime.now();
}

class FactoryService {
  FactoryService._();

  /// قائمة المصانع — مع بحث اختياري وتصفية بالفئة.
  static Future<List<SFFactory>> list({
    String? category,
    String? region,
    String? search,
    int limit = 60,
  }) async {
    var q = sb.from('factories').select(kFactorySelect);
    if (region != null && region.isNotEmpty) q = q.eq('region_id', region);

    if (category != null && category.isNotEmpty) {
      // مفتاح الربط هو الاسم الإنجليزي للفئة — كما يخزّنه عمود industry.
      q = q.eq('industry', category);
    }
    if (search != null && search.trim().isNotEmpty) {
      q = q.ilike('name', '%${search.trim()}%');
    }

    final rows = await q.order('created_at', ascending: false).limit(limit);
    // المدير قد يقرأ كل المصانع عبر RLS، لكن الدليل العام يعرض
    // المعتمد ومصنع المستخدم نفسه فقط، مثل صفحة الويب.
    return rows
        .map((e) => SFFactory(Map<String, dynamic>.from(e as Map)))
        .where((factory) => factory.isApproved || factory.isMine)
        .toList();
  }

  static Future<SFFactory?> byId(int id) async {
    if (id <= 0) return null;
    final row = await sb
        .from('factories')
        .select(kFactorySelect)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : SFFactory(Map<String, dynamic>.from(row));
  }

  /// مصنع المستخدم الحالي — يُستخدم لرابط "مصنعي".
  static Future<SFFactory?> mine() async {
    final uid = AuthService.instance.user?.id;
    if (uid == null) return null;
    final row = await sb
        .from('factories')
        .select(kFactorySelect)
        .eq('owner_id', uid)
        .maybeSingle();
    return row == null ? null : SFFactory(Map<String, dynamic>.from(row));
  }

  static Future<List<SFProduct>> products(
    int factoryId, {
    int limit = 100,
  }) async {
    final rows = await sb
        .from('products')
        .select(
          'id, client_key, factory_id, name, price, tiers, image, images, sort_order, description, material, sizes, colors, moq',
        )
        .eq('factory_id', factoryId)
        .order('sort_order')
        .limit(limit);
    return rows
        .map((e) => SFProduct(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<SFProduct?> productById(int id) async {
    if (id <= 0) return null;
    final row = await sb
        .from('products')
        .select(
          'id, client_key, factory_id, name, price, tiers, image, images, description, material, sizes, colors, moq, factories(name, status)',
        )
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : SFProduct(Map<String, dynamic>.from(row));
  }

  /// منتجات للواجهة الرئيسية — أحدث ما نُشر.
  static Future<List<SFProduct>> latestProducts({int limit = 24}) async {
    final rows = await sb
        .from('products')
        .select(
          'id, factory_id, name, price, tiers, image, images, description, material, sizes, colors, moq, factories(name, status)',
        )
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((e) => SFProduct(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<SFPost>> posts(int factoryId, {int limit = 50}) async {
    final rows = await sb
        .from('posts')
        .select('id, client_key, factory_id, body, image, video, created_at')
        .eq('factory_id', factoryId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((e) => SFPost(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// حفظ بيانات المصنع. [expectedUpdatedAt] يمنع الكتابة فوق
  /// تعديل جرى في جلسة أخرى (يُرفض بالرمز 40001).
  static Future<dynamic> save({
    required int factoryId,
    required Map<String, dynamic> factory,
    List<Map<String, dynamic>>? products,
    List<Map<String, dynamic>>? posts,
    String? expectedUpdatedAt,
  }) {
    return sb.rpc(
      'save_factory_content',
      params: {
        'p_factory_id': factoryId,
        'p_factory': factory,
        'p_products': ?products,
        'p_posts': ?posts,
        'p_expected_updated_at': ?expectedUpdatedAt,
      },
    );
  }

  /// لوحة الإدارة: تغيير حالة مصنع.
  ///
  /// القيم المسموحة في القاعدة: pending / approved / rejected.
  /// إرسال "approve" (بلا d) يُرفض بقيد factories_status_check —
  /// وهي علّة شحنت مرة وعطّلت الاعتماد كلياً.
  static Future<void> setStatus(
    int factoryId,
    String status, {
    String reason = '',
  }) async {
    const allowed = {'pending', 'approved', 'rejected'};
    final value = status == 'approve' ? 'approved' : status;
    if (!allowed.contains(value)) {
      throw Exception('حالة غير صالحة: $status');
    }
    final updated = await sb
        .from('factories')
        .update({
          'status': value,
          'rejection_reason': value == 'rejected' ? reason.trim() : '',
        })
        .eq('id', factoryId)
        .select();
    if (updated.isEmpty) {
      throw StateError('لم يُحدّث المصنع؛ تحقّق من الصلاحيات.');
    }
  }

  static Future<List<SFFactory>> adminList() async {
    if (AuthService.instance.profile?.isAdmin != true) return [];
    final rows = await sb
        .from('factories')
        .select(kFactorySelect)
        .order('created_at', ascending: false);
    return rows
        .map((row) => SFFactory(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// المصانع المعلّقة — لصفحة الإدارة.
  static Future<List<SFFactory>> pending() async {
    final rows = await sb
        .from('factories')
        .select(kFactorySelect)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return rows
        .map((e) => SFFactory(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

/// روابط الوسائط لا تقبل مخططات التنفيذ أو البيانات المضمّنة.
String safeMediaUrl(dynamic value) {
  if (value is! String) return '';
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty
      ? uri.toString()
      : '';
}

/// يكمّل أسماء المواقع المكتوبة بلا https كما في محرّر الويب.
Uri? normalizedWebsite(String raw) {
  final value = raw.trim();
  if (value.isEmpty || RegExp(r'\s').hasMatch(value)) return null;
  final hasScheme = RegExp(
    r'^[a-z][a-z0-9+.-]*:',
    caseSensitive: false,
  ).hasMatch(value);
  final candidate = hasScheme ? value : 'https://$value';
  final safe = safeMediaUrl(candidate);
  if (safe.isEmpty) return null;
  final uri = Uri.parse(safe);
  if (!hasScheme && !uri.host.contains('.')) return null;
  return uri;
}
