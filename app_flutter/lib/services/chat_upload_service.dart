import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../core/uuid.dart';
import 'auth_service.dart';

class SFChatUpload {
  const SFChatUpload({
    required this.path,
    required this.url,
    required this.type,
  });
  final String path;
  final String url;
  final String type;

  static Future<SFChatUpload?> pick({bool video = false}) async {
    final uid = AuthService.instance.user?.id;
    if (uid == null) throw StateError('يجب تسجيل الدخول أولاً');
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 85,
          );
    if (file == null) return null;
    final ext = file.name.split('.').last.toLowerCase();
    final types = video
        ? {'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime'}
        : {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'webp': 'image/webp',
            'gif': 'image/gif',
          };
    if (!types.containsKey(ext)) throw StateError('نوع الملف غير مسموح');
    if (await file.length() > (video ? 50 : 5) * 1024 * 1024) {
      throw StateError('حجم الملف أكبر من الحد المسموح');
    }
    if (AuthService.instance.user?.id != uid) {
      throw StateError('تغيّرت الجلسة؛ أعد المحاولة');
    }
    final path = '$uid/messages/${newUuidV4()}.$ext';
    final bucket = sb.storage.from(SFBuckets.chatMedia);
    await bucket.uploadBinary(
      path,
      await file.readAsBytes(),
      fileOptions: FileOptions(contentType: types[ext]),
    );
    try {
      return SFChatUpload(
        path: path,
        url: await bucket.createSignedUrl(path, 3600),
        type: video ? 'video' : 'image',
      );
    } catch (_) {
      await bucket.remove([path]);
      rethrow;
    }
  }

  Future<void> remove() => sb.storage.from(SFBuckets.chatMedia).remove([path]);
}
