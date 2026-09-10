// إعلانات الرئيسية: الحفظ على الخادم والكتابة لمدير الموقع فقط.
import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';
import 'auth_service.dart';

class SFPromotion {
  const SFPromotion({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.targetUrl = '',
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final String imageUrl;
  final String targetUrl;
  final bool isActive;
  final int sortOrder;

  factory SFPromotion.fromJson(Map<String, dynamic> json) => SFPromotion(
    id: json['id'] as String,
    title: json['title'] as String,
    imageUrl: json['image_url'] as String,
    targetUrl: json['target_url'] as String? ?? '',
    isActive: json['is_active'] == true,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'image_url': imageUrl,
    'target_url': targetUrl,
    'is_active': isActive,
    'sort_order': sortOrder,
  };

  /// رموز الأخطاء ثابتة لتترجمها الواجهة إلى لغة المستخدم.
  static void validateInput({
    required String title,
    required String imageUrl,
    required String targetUrl,
    required int sortOrder,
  }) {
    if (title.trim().isEmpty || title.trim().runes.length > 120) {
      throw const FormatException('promotion_title_invalid');
    }
    if (PromotionService.imagePath(imageUrl.trim()) == null) {
      throw const FormatException('promotion_image_required');
    }
    if (!isValidTargetUrl(targetUrl)) {
      throw const FormatException('promotion_link_invalid');
    }
    if (sortOrder < 0 || sortOrder > 9999) {
      throw const FormatException('promotion_order_invalid');
    }
  }

  /// لا تُفتح مخططات محلية أو روابط تتضمن بيانات دخول.
  static bool isValidTargetUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed.length > 2048 || RegExp(r'\s').hasMatch(trimmed)) {
      return false;
    }
    final uri = Uri.tryParse(trimmed);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }
}

class PromotionService {
  PromotionService._();

  static const bucket = 'promotion-media';
  static final changes = ValueNotifier<int>(0);
  static const _table = 'home_promotions';
  static const _columns = 'id,title,image_url,target_url,is_active,sort_order';

  static void _requireAdmin() {
    if (!AuthService.instance.isSignedIn ||
        AuthService.instance.profile?.isAdmin != true) {
      throw StateError('promotion_admin_required');
    }
  }

  static Future<List<SFPromotion>> listPublic() async {
    final rows = await sb
        .from(_table)
        .select(_columns)
        .eq('is_active', true)
        .order('sort_order')
        .order('created_at')
        .order('id');
    return rows.map(SFPromotion.fromJson).toList(growable: false);
  }

  static Future<List<SFPromotion>> listAdmin() async {
    _requireAdmin();
    final rows = await sb
        .from(_table)
        .select(_columns)
        .order('sort_order')
        .order('created_at')
        .order('id');
    return rows.map(SFPromotion.fromJson).toList(growable: false);
  }

  static Future<SFPromotion> save({
    SFPromotion? existing,
    required String title,
    required String imageUrl,
    required String targetUrl,
    required bool isActive,
    required int sortOrder,
  }) async {
    _requireAdmin();
    SFPromotion.validateInput(
      title: title,
      imageUrl: imageUrl,
      targetUrl: targetUrl,
      sortOrder: sortOrder,
    );
    final values = {
      'title': title.trim(),
      'image_url': imageUrl.trim(),
      'target_url': targetUrl.trim(),
      'is_active': isActive,
      'sort_order': sortOrder,
    };
    final Map<String, dynamic> row;
    if (existing == null) {
      row = await sb.from(_table).insert(values).select(_columns).single();
    } else {
      row = await sb
          .from(_table)
          .update(values)
          .eq('id', existing.id)
          .select(_columns)
          .single();
    }
    final promotion = SFPromotion.fromJson(row);
    changes.value++;
    return promotion;
  }

  static Future<void> setActive(SFPromotion promotion, bool active) async {
    _requireAdmin();
    // single يجعل اختفاء السجل أو رفض الصلاحية خطأً لا نجاحاً وهمياً.
    await sb
        .from(_table)
        .update({'is_active': active})
        .eq('id', promotion.id)
        .select('id')
        .single();
    changes.value++;
  }

  static Future<void> delete(SFPromotion promotion) async {
    _requireAdmin();
    await sb.from(_table).delete().eq('id', promotion.id).select('id').single();
    changes.value++;
  }

  /// يقبل رابط الدلو الحالي فقط، ويرفض المسارات الملتبسة أو الخارجية.
  static String? imagePath(String imageUrl) {
    if (imageUrl.length > 2048) return null;
    final uri = Uri.tryParse(imageUrl);
    final project = Uri.parse(kSupabaseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != project.host ||
        uri.port != project.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final prefix = '/storage/v1/object/public/$bucket/';
    if (!uri.path.startsWith(prefix)) return null;
    final path = uri.path.substring(prefix.length);
    if (!RegExp(
      r'^[0-9a-fA-F-]{36}/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|gif)$',
      caseSensitive: false,
    ).hasMatch(path)) {
      return null;
    }
    return path;
  }

  /// تنظيف مسودة رفعها هذا المدير ولم تعد مرتبطة بأي إعلان.
  /// لا يحذف صورة مدير آخر، أو صورة إعلان منشور/مخفي، أو رابطاً خارجياً.
  static Future<void> cleanupUploadedImage(String imageUrl) async {
    _requireAdmin();
    final path = imagePath(imageUrl);
    final uid = AuthService.instance.user!.id;
    if (path == null || !path.startsWith('$uid/')) return;
    final used = await sb
        .from(_table)
        .select('id')
        .eq('image_url', imageUrl)
        .limit(1);
    if (used.isNotEmpty) return;
    // سياسة الحذف بالخادم تعيد فحص الارتباط قبل حذف الملف.
    await sb.storage.from(bucket).remove([path]);
  }
}
