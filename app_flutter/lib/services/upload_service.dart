// ============================================================
//  رفع الوسائط — مقابل media-upload.js
//
//  الصلاحيات تفرضها سياسات Storage في الخادم؛ المفتاح العام
//  وحده يكفي هنا. لا تضع مفاتيح سرية في هذا الملف.
//
//  المسار: <user-id>/<folder>/<uuid>.<ext>
// ============================================================

import 'dart:io';
import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'auth_service.dart';

class SFUpload {
  SFUpload._();

  static const int maxImageBytes = 5 * 1024 * 1024;
  static const int maxVideoBytes = 50 * 1024 * 1024;

  static const List<String> _imageExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'];
  static const List<String> _videoExt = ['mp4', 'webm', 'mov'];

  static String _ext(String path) {
    final i = path.lastIndexOf('.');
    return i == -1 ? 'bin' : path.substring(i + 1).toLowerCase();
  }

  static String _mime(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      default:
        return 'application/octet-stream';
    }
  }

  static String _uuid() {
    final r = Random.secure();
    final chars = List<String>.generate(
        32, (_) => r.nextInt(16).toRadixString(16));
    return chars.join();
  }

  /// يرفع ملفاً ويعيد رابطه العام.
  ///
  /// مهم: احفظ في القاعدة هذا الرابط فقط — لا base64. دالة
  /// save_factory_content تقصّ كل قيمة عند 2048 محرفاً، وهو حجم
  /// يكفي رابطاً ولا يكفي صورة مضمّنة (انظر CLAUDE.md).
  static Future<String> uploadFile(
    File file, {
    required String bucket,
    String folder = 'media',
    bool isVideo = false,
  }) async {
    if (AuthService.instance.user == null) {
      throw Exception('يجب تسجيل الدخول لرفع الملفات');
    }

    final ext = _ext(file.path);
    final allowed = isVideo ? _videoExt : _imageExt;
    if (!allowed.contains(ext)) throw Exception('نوع الملف غير مسموح');

    final size = await file.length();
    final max = isVideo ? maxVideoBytes : maxImageBytes;
    if (size > max) throw Exception('حجم الملف أكبر من الحد المسموح');

    final uid = AuthService.instance.user!.id;
    final path = '$uid/$folder/${_uuid()}.$ext';

    await sb.storage.from(bucket).upload(
          path,
          file,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: _mime(ext),
          ),
        );

    return sb.storage.from(bucket).getPublicUrl(path);
  }

  /// يفتح المعرض ويرفع صورة بعد تصغيرها.
  ///
  /// التصغير مقصود: الصورة من كاميرا الجوال قد تتجاوز الحدّ،
  /// وهذه كانت علّة حقيقية في نسخة الويب.
  static Future<String?> pickAndUploadImage({
    required String bucket,
    String folder = 'media',
    int maxSize = 1280,
  }) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSize.toDouble(),
      maxHeight: maxSize.toDouble(),
      imageQuality: 85,
    );
    if (picked == null) return null;
    return uploadFile(File(picked.path), bucket: bucket, folder: folder);
  }
}
