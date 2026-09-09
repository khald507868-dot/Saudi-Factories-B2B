import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/supabase_config.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import '../services/upload_service.dart';
import 'common.dart';

class CategoryImageAdmin extends StatefulWidget {
  const CategoryImageAdmin({super.key});
  @override
  State<CategoryImageAdmin> createState() => _CategoryImageAdminState();
}

class _CategoryImageAdminState extends State<CategoryImageAdmin> {
  late Future<Map<String, String>> _images = CatalogService.categoryImages();
  String? _busy;
  Future<void> _change(String category, {bool remove = false}) async {
    if (AuthService.instance.profile?.isAdmin != true) return;
    setState(() => _busy = category);
    try {
      if (remove) {
        await sb.from('category_images').delete().eq('category_en', category);
      } else {
        final url = await SFUpload.pickAndUploadImage(
          bucket: SFBuckets.factoryMedia,
          folder: 'categories',
          maxSize: 640,
        );
        if (url == null) return;
        await sb.from('category_images').upsert({
          'category_en': category,
          'image_url': url,
        }, onConflict: 'category_en');
      }
      if (mounted) setState(() => _images = CatalogService.categoryImages());
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>>(
    future: _images,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return SFStateView(message: context.t('fx_loading'), loading: true);
      }
      if (snapshot.hasError) {
        return SFStateView(
          message: context.t('fx_failed'),
          onRetry: () =>
              setState(() => _images = CatalogService.categoryImages()),
        );
      }
      final images = snapshot.data ?? {};
      return ListView(
        children: [
          for (final category in context.i18n.categories)
            ListTile(
              leading: SFImage(
                url: images[category['en']] ?? '',
                width: 50,
                height: 50,
              ),
              title: Text(context.i18n.categoryName(category)),
              trailing: _busy == category['en']
                  ? const CircularProgressIndicator()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _busy != null
                              ? null
                              : () => _change(category['en']!),
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                        ),
                        if (images.containsKey(category['en']))
                          IconButton(
                            onPressed: _busy != null
                                ? null
                                : () => _change(category['en']!, remove: true),
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
            ),
        ],
      );
    },
  );
}
