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
    final s = v as String?;
    if (s == null || !s.startsWith('http')) return '';
    return s;
  }
}

class SFProduct {
  SFProduct(this.raw);

  final Map<String, dynamic> raw;

  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  int get factoryId => (raw['factory_id'] as num?)?.toInt() ?? 0;
  String get name => (raw['name'] as String?) ?? '';
  double get price => (raw['price'] as num?)?.toDouble() ?? 0;

  /// يُفضّل images[] على image — انظر تعليق CartItem.
  String get image {
    final images = raw['images'];
    if (images is List) {
      for (final u in images) {
        if (u is String && u.startsWith('http')) return u;
      }
    }
    final single = raw['image'];
    if (single is String && single.startsWith('http')) return single;
    return '';
  }
}

class SFPost {
  SFPost(this.raw);

  final Map<String, dynamic> raw;

  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  String get body => (raw['body'] as String?) ?? '';
  String get image {
    final s = raw['image'] as String?;
    return (s != null && s.startsWith('http')) ? s : '';
  }

  DateTime get createdAt =>
      DateTime.tryParse('${raw['created_at']}')?.toLocal() ?? DateTime.now();
}

class FactoryService {
  FactoryService._();

  /// قائمة المصانع — مع بحث اختياري وتصفية بالفئة.
  static Future<List<SFFactory>> list({
    String? category,
    String? search,
    int limit = 60,
  }) async {
    var q = sb.from('factories').select(kFactorySelect);

    if (category != null && category.isNotEmpty) {
      // مفتاح الربط هو الاسم الإنجليزي للفئة — كما يخزّنه عمود industry.
      q = q.eq('industry', category);
    }
    if (search != null && search.trim().isNotEmpty) {
      q = q.ilike('name', '%${search.trim()}%');
    }

    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows
        .map((e) => SFFactory(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<SFFactory?> byId(int id) async {
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

  static Future<List<SFProduct>> products(int factoryId,
      {int limit = 100}) async {
    final rows = await sb
        .from('products')
        .select('id, factory_id, name, price, image, images, sort_order')
        .eq('factory_id', factoryId)
        .order('sort_order')
        .limit(limit);
    return rows
        .map((e) => SFProduct(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// منتجات للواجهة الرئيسية — أحدث ما نُشر.
  static Future<List<SFProduct>> latestProducts({int limit = 24}) async {
    final rows = await sb
        .from('products')
        .select(
            'id, factory_id, name, price, image, images, factories(name)')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((e) => SFProduct(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<SFPost>> posts(int factoryId, {int limit = 50}) async {
    try {
      final rows = await sb
          .from('posts')
          .select('id, factory_id, body, image, created_at')
          .eq('factory_id', factoryId)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .map((e) => SFPost(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
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
    return sb.rpc('save_factory_content', params: {
      'p_factory_id': factoryId,
      'p_factory': factory,
      if (products != null) 'p_products': products,
      if (posts != null) 'p_posts': posts,
      if (expectedUpdatedAt != null)
        'p_expected_updated_at': expectedUpdatedAt,
    });
  }

  /// لوحة الإدارة: تغيير حالة مصنع.
  ///
  /// القيم المسموحة في القاعدة: pending / approved / rejected.
  /// إرسال "approve" (بلا d) يُرفض بقيد factories_status_check —
  /// وهي علّة شحنت مرة وعطّلت الاعتماد كلياً.
  static Future<void> setStatus(int factoryId, String status) async {
    const allowed = {'pending', 'approved', 'rejected'};
    final value = status == 'approve' ? 'approved' : status;
    if (!allowed.contains(value)) {
      throw Exception('حالة غير صالحة: $status');
    }
    await sb
        .from('factories')
        .update({'status': value})
        .eq('id', factoryId)
        .select();
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
