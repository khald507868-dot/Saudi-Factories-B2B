// إعلانات الرئيسية: الحفظ على الخادم والكتابة لمدير الموقع فقط.
import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';
import 'auth_service.dart';

class SFVideoPromotion {
  const SFVideoPromotion({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.videoUrl,
    this.logoUrl = '',
    this.targetUrl = '',
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final String imageUrl;
  final String videoUrl;
  final String logoUrl;
  final String targetUrl;
  final bool isActive;
  final int sortOrder;

  factory SFVideoPromotion.fromJson(Map<String, dynamic> json) =>
      SFVideoPromotion(
        id: json['id'] as String,
        title: json['title'] as String,
        imageUrl: json['image_url'] as String,
        videoUrl: json['video_url'] as String,
        logoUrl: json['logo_url'] as String? ?? '',
        targetUrl: json['target_url'] as String? ?? '',
        isActive: json['is_active'] == true,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'image_url': imageUrl,
    'video_url': videoUrl,
    'logo_url': logoUrl,
    'target_url': targetUrl,
    'is_active': isActive,
    'sort_order': sortOrder,
  };

  /// رموز الأخطاء ثابتة لتترجمها الواجهة إلى لغة المستخدم.
  static void validateInput({
    required String title,
    required String imageUrl,
    required String videoUrl,
    String logoUrl = '',
    required String targetUrl,
    required int sortOrder,
  }) {
    if (title.trim().isEmpty || title.trim().runes.length > 120) {
      throw const FormatException('promotion_title_invalid');
    }
    if (VideoPromotionService.imagePath(imageUrl.trim()) == null) {
      throw const FormatException('promotion_image_required');
    }
    if (VideoPromotionService.imagePath(videoUrl.trim(), video: true) == null) {
      throw const FormatException('video_required');
    }
    if (logoUrl.isNotEmpty &&
        VideoPromotionService.imagePath(logoUrl.trim()) == null) {
      throw const FormatException('logo_invalid');
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

class VideoPromotionService {
  VideoPromotionService._();

  static const bucket = 'video-promotion-media';
  static final changes = ValueNotifier<int>(0);
  static const _table = 'home_video_promotions';
  static const _columns =
      'id,title,image_url,video_url,logo_url,target_url,is_active,sort_order';

  static void _requireAdmin() {
    if (!AuthService.instance.isSignedIn ||
        AuthService.instance.profile?.isAdmin != true) {
      throw StateError('promotion_admin_required');
    }
  }

  static Future<List<SFVideoPromotion>> listPublic() async {
    final rows = await sb
        .from(_table)
        .select(_columns)
        .eq('is_active', true)
        .order('sort_order')
        .order('created_at')
        .order('id');
    return rows.map(SFVideoPromotion.fromJson).toList(growable: false);
  }

  static Future<List<SFVideoPromotion>> listAdmin() async {
    _requireAdmin();
    final rows = await sb
        .from(_table)
        .select(_columns)
        .order('sort_order')
        .order('created_at')
        .order('id');
    return rows.map(SFVideoPromotion.fromJson).toList(growable: false);
  }

  static Future<SFVideoPromotion> save({
    SFVideoPromotion? existing,
    required String title,
    required String imageUrl,
    required String videoUrl,
    String logoUrl = '',
    required String targetUrl,
    required bool isActive,
    required int sortOrder,
  }) async {
    _requireAdmin();
    SFVideoPromotion.validateInput(
      title: title,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      logoUrl: logoUrl,
      targetUrl: targetUrl,
      sortOrder: sortOrder,
    );
    final values = {
      'title': title.trim(),
      'image_url': imageUrl.trim(),
      'video_url': videoUrl.trim(),
      'logo_url': logoUrl.trim(),
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
    final promotion = SFVideoPromotion.fromJson(row);
    if (existing != null) {
      for (final url in [
        existing.imageUrl,
        existing.videoUrl,
        existing.logoUrl,
      ]) {
        if (url.isEmpty ||
            [
              promotion.imageUrl,
              promotion.videoUrl,
              promotion.logoUrl,
            ].contains(url)) {
          continue;
        }
        try {
          await cleanupUploadedImage(url);
        } catch (_) {
          /* يبقى الملف عند تعذر التنظيف. */
        }
      }
    }
    changes.value++;
    return promotion;
  }

  static Future<void> setActive(SFVideoPromotion promotion, bool active) async {
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

  static Future<void> delete(SFVideoPromotion promotion) async {
    _requireAdmin();
    await sb.from(_table).delete().eq('id', promotion.id).select('id').single();
    for (final url in [
      promotion.imageUrl,
      promotion.videoUrl,
      promotion.logoUrl,
    ]) {
      if (url.isEmpty) continue;
      try {
        await cleanupUploadedImage(url);
      } catch (_) {
        /* الحذف تم؛ التنظيف مستقل. */
      }
    }
    changes.value++;
  }

  /// يقبل رابط الدلو الحالي فقط، ويرفض المسارات الملتبسة أو الخارجية.
  static String? imagePath(String imageUrl, {bool video = false}) {
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
      r'^[0-9a-fA-F-]{36}/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(' +
          (video ? 'mp4|webm|mov' : 'jpg|jpeg|png|webp|gif') +
          r')$',
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
    final path = imagePath(imageUrl) ?? imagePath(imageUrl, video: true);
    final uid = AuthService.instance.user!.id;
    if (path == null || !path.startsWith('$uid/')) return;
    final used = await sb
        .from(_table)
        .select('id')
        .or(
          'image_url.eq.$imageUrl,video_url.eq.$imageUrl,logo_url.eq.$imageUrl',
        )
        .limit(1);
    if (used.isNotEmpty) return;
    // سياسة الحذف بالخادم تعيد فحص الارتباط قبل حذف الملف.
    await sb.storage.from(bucket).remove([path]);
  }
}
