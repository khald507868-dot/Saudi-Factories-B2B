import '../core/supabase_config.dart';
import 'auth_service.dart';
import 'factory_service.dart';

class SFFollowState {
  const SFFollowState({required this.followers, required this.isFollowing});
  final int followers;
  final bool isFollowing;

  factory SFFollowState.fromJson(Map<String, dynamic> json) => SFFollowState(
    followers: (json['followers'] as num?)?.toInt() ?? 0,
    isFollowing: json['is_following'] == true,
  );
}

class CatalogService {
  CatalogService._();

  static Future<Map<String, String>> categoryImages() async {
    final rows = await sb
        .from('category_images')
        .select('category_en, image_url');
    return {
      for (final row in rows)
        if (safeMediaUrl(row['image_url']).isNotEmpty)
          row['category_en'] as String: safeMediaUrl(row['image_url']),
    };
  }

  static Future<SFFollowState> follows(int factoryId) async {
    final result = await sb.rpc(
      'get_factory_follows',
      params: {'p_factory_id': factoryId},
    );
    return SFFollowState.fromJson(Map<String, dynamic>.from(result as Map));
  }

  static Future<SFFollowState> setFollowing(
    SFFactory factory,
    bool follow,
  ) async {
    final userId = AuthService.instance.user?.id;
    if (userId == null || factory.ownerId == userId) {
      throw StateError('لا يمكن متابعة هذا المصنع');
    }
    if (follow) {
      await sb
          .from('factory_follows')
          .upsert(
            {'factory_id': factory.id, 'user_id': userId},
            onConflict: 'user_id,factory_id',
            ignoreDuplicates: true,
          );
    } else {
      await sb
          .from('factory_follows')
          .delete()
          .eq('factory_id', factory.id)
          .eq('user_id', userId);
    }
    return follows(factory.id);
  }
}
