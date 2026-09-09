// ============================================================
//  تحرير المصنع — الجزء القابل للتعديل من app-factory.html
//
//  الحفظ عبر الدالة save_factory_content: تتحقّق من الملكية
//  في الخادم وتقصّ كل قيمة عند 2048 محرفاً. لذلك تُرسل روابط
//  التخزين فقط — صورة base64 تصل مبتورة وتظهر مربّعاً رمادياً.
//
//  updated_at يُرسل كطابع تفاؤلي: إن عُدِّل المصنع في جلسة
//  أخرى يرفض الخادم الحفظ (40001) بدل الكتابة فوق عمل غيرنا.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/supabase_config.dart';
import '../core/theme.dart';
import '../core/uuid.dart';
import '../services/factory_service.dart';
import '../services/upload_service.dart';
import '../widgets/common.dart';

class FactoryEditPage extends StatefulWidget {
  const FactoryEditPage({super.key, required this.factory});

  final SFFactory factory;

  @override
  State<FactoryEditPage> createState() => _FactoryEditPageState();
}

class _FactoryEditPageState extends State<FactoryEditPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.factory.name,
  );
  late final TextEditingController _about = TextEditingController(
    text: widget.factory.about,
  );
  late final TextEditingController _website = TextEditingController(
    text: widget.factory.website,
  );
  late final TextEditingController _companySize = TextEditingController(
    text: widget.factory.companySize,
  );

  late String _cover = widget.factory.cover;
  late String _logo = widget.factory.logo;
  late String _industry = widget.factory.industry;
  late String _region = widget.factory.regionId;
  late String? _expectedUpdatedAt = widget.factory.updatedAt;
  late final Map<String, TextEditingController> _address = {
    for (final key in [
      'commercial_register',
      'industrial_license',
      'address_city',
      'address_district',
      'address_short',
      'address_building',
      'address_secondary',
      'address_postal',
      'address_street',
    ])
      key: TextEditingController(text: '${widget.factory.raw[key] ?? ''}'),
  };

  bool _saving = false;
  String? _uploadingWhat;
  final List<Map<String, dynamic>> _products = [];
  final List<Map<String, dynamic>> _posts = [];
  bool _loadingContent = true;
  Object? _contentError;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() {
      _loadingContent = true;
      _contentError = null;
    });
    try {
      final content = await Future.wait([
        FactoryService.products(widget.factory.id, limit: 200),
        FactoryService.posts(widget.factory.id, limit: 200),
      ]);
      if (!mounted) return;
      setState(() {
        _products.clear();
        for (final product in content[0] as List<SFProduct>) {
          _products.add({
            ...product.raw,
            'client_key': product.raw['client_key'] ?? newUuidV4(),
            'images': product.images,
            'tiers': product.tiers.map((tier) => tier.toJson()).toList(),
          });
        }
        _posts.clear();
        _posts.addAll(
          (content[1] as List<SFPost>).map(
            (post) => {
              ...post.raw,
              'client_key': post.raw['client_key'] ?? newUuidV4(),
            },
          ),
        );
        _loadingContent = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _contentError = error;
          _loadingContent = false;
        });
      }
    }
  }

  Future<void> _pickContentImage(
    Map<String, dynamic> item, {
    required bool product,
  }) async {
    if (_uploadingWhat != null || _saving) return;
    final key = '${item['client_key']}';
    setState(() => _uploadingWhat = key);
    try {
      final url = await SFUpload.pickAndUploadImage(
        bucket: SFBuckets.factoryMedia,
        folder: product ? 'products' : 'posts',
      );
      if (!mounted || url == null) return;
      setState(() {
        if (product) {
          (item['images'] as List).add(url);
        } else {
          item['image'] = url;
        }
      });
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _uploadingWhat = null);
    }
  }

  @override
  void dispose() {
    for (final controller in _address.values) {
      controller.dispose();
    }
    _name.dispose();
    _about.dispose();
    _website.dispose();
    _companySize.dispose();
    super.dispose();
  }

  Future<void> _pick(String which) async {
    setState(() => _uploadingWhat = which);
    try {
      final url = await SFUpload.pickAndUploadImage(
        bucket: SFBuckets.factoryMedia,
        folder: which,
        maxSize: which == 'logo' ? 360 : 1280,
      );
      if (url == null) return;
      if (!mounted) return;
      setState(() {
        if (which == 'logo') {
          _logo = url;
        } else {
          _cover = url;
        }
      });
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    } finally {
      if (mounted) setState(() => _uploadingWhat = null);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _uploadingWhat != null ||
        _loadingContent ||
        _contentError != null) {
      return;
    }
    final websiteInput = _website.text.trim();
    final website = normalizedWebsite(websiteInput)?.toString() ?? '';
    // الخادم يرفض رابطاً لا يبدأ بـ http/https، فنمنعه مبكراً
    // برسالة مفهومة بدل خطأ قاعدة بيانات.
    if (websiteInput.isNotEmpty && website.isEmpty) {
      showSFError(context, Exception(context.t('factory_invalid_website')));
      return;
    }
    final cleanProducts = <Map<String, dynamic>>[];
    for (final product in _products) {
      final tiers = <Map<String, dynamic>>[];
      for (final tier in product['tiers'] as List) {
        final min = int.tryParse('${tier['min']}');
        final maxText = '${tier['max'] ?? ''}'.trim();
        final max = maxText.isEmpty ? null : int.tryParse(maxText);
        final priceText = '${tier['price']}'.trim();
        final price = double.tryParse(priceText);
        if (min == null ||
            min < 1 ||
            min > 2147483647 ||
            (maxText.isNotEmpty &&
                (max == null || max < min || max > 2147483647)) ||
            price == null ||
            !price.isFinite ||
            price <= 0 ||
            price > 9999999999.99 ||
            !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(priceText)) {
          showSFError(context, Exception(context.t('factory_invalid_tier')));
          return;
        }
        tiers.add({'min': min, 'max': max, 'price': price.toStringAsFixed(2)});
      }
      tiers.sort((a, b) => (a['min'] as int).compareTo(b['min'] as int));
      final moqText = '${product['moq'] ?? ''}'.trim();
      final moq = moqText.isEmpty ? null : int.tryParse(moqText);
      if (moqText.isNotEmpty && (moq == null || moq < 1 || moq > 2147483647)) {
        showSFError(context, Exception(context.t('factory_invalid_moq')));
        return;
      }
      // السعر القديم يُحفظ كشبكة أمان للخادم ولا يُعرض كحقل مستقل.
      cleanProducts.add({...product, 'tiers': tiers, 'moq': moq});
    }

    setState(() => _saving = true);
    try {
      final saved = await FactoryService.save(
        factoryId: widget.factory.id,
        factory: {
          'name': _name.text.trim(),
          'about': _about.text.trim(),
          'website': website,
          'industry': _industry,
          'company_size': _companySize.text.trim(),
          // روابط تخزين فقط — لا base64.
          'cover': _cover,
          'logo': _logo,
        },
        expectedUpdatedAt: _expectedUpdatedAt,
        products: cleanProducts,
        posts: _posts,
      );
      if (saved is Map && saved['factory'] is Map) {
        _expectedUpdatedAt = saved['factory']['updated_at'] as String?;
      }
      // محرّر الويب يحفظ العنوان والسجل مباشرة؛ RPC المحتوى لا تتعامل معهما.
      final addressChanges = <String, dynamic>{
        if (_region != widget.factory.regionId) 'region_id': _region,
        for (final entry in _address.entries)
          if (entry.value.text.trim() !=
              '${widget.factory.raw[entry.key] ?? ''}')
            entry.key: entry.value.text.trim(),
      };
      if (addressChanges.isNotEmpty) {
        var update = sb
            .from('factories')
            .update(addressChanges)
            .eq('id', widget.factory.id);
        if (_expectedUpdatedAt != null) {
          update = update.eq('updated_at', _expectedUpdatedAt!);
        }
        final rows = await update.select('updated_at');
        if (rows.isEmpty) {
          throw StateError(
            'حُفظ المحتوى، لكن تعذّر حفظ العنوان بسبب تعديل متزامن. أعد فتح المصنع.',
          );
        }
        _expectedUpdatedAt = rows.first['updated_at'] as String?;
      }
      if (!mounted) return;
      showSFMessage(context, context.t('saved_msg'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      showSFError(
        context,
        msg.contains('40001')
            ? Exception(context.t('factory_edit_conflict'))
            : e,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final cats = i18n.categories;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(title: Text(i18n.t('btn_update'))),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // الغلاف
            Text(
              i18n.t('factory_cover_hint'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _uploadingWhat != null ? null : () => _pick('cover'),
              borderRadius: BorderRadius.circular(SFMetrics.radius),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SFImage(url: _cover, height: 130),
                  if (_uploadingWhat == 'cover')
                    const CircularProgressIndicator(color: SFColors.white)
                  else
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: SFColors.white,
                      size: 28,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // الشعار
            Row(
              children: [
                InkWell(
                  onTap: _uploadingWhat != null ? null : () => _pick('logo'),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SFImage(
                        url: _logo,
                        width: 72,
                        height: 72,
                        placeholderIcon: Icons.factory_outlined,
                      ),
                      if (_uploadingWhat == 'logo')
                        const CircularProgressIndicator(
                          color: SFColors.white,
                          strokeWidth: 2,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    i18n.t('field_company_image'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: SFColors.muted2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            _Labelled(
              label: i18n.t('factory_name_label'),
              child: TextField(
                controller: _name,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            _Labelled(
              label: i18n.t('factory_about_label'),
              child: TextField(
                controller: _about,
                maxLines: 5,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            _Labelled(
              label: i18n.t('field_industry'),
              child: DropdownButtonFormField<String>(
                // القيمة المخزّنة هي الاسم الإنجليزي — مفتاح الربط
                // مع عمود industry، والمعروض بلغة المستخدم.
                initialValue:
                    cats.any((cat) => i18n.categoryKey(cat) == _industry)
                    ? _industry
                    : null,
                isExpanded: true,
                items: cats
                    .map(
                      (c) => DropdownMenuItem(
                        value: i18n.categoryKey(c),
                        child: Text(
                          i18n.categoryName(c),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _industry = v ?? ''),
              ),
            ),
            _Labelled(
              label: i18n.t('field_company_size'),
              child: TextField(
                controller: _companySize,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(hintText: '51-200'),
              ),
            ),
            _Labelled(
              label: i18n.t('field_website'),
              child: TextField(
                controller: _website,
                keyboardType: TextInputType.url,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'https://example.com',
                ),
              ),
            ),

            _Labelled(
              label: i18n.t('region_choose'),
              child: DropdownButtonFormField<String>(
                initialValue: i18n.regionName(_region) == _region
                    ? null
                    : _region,
                items: [
                  for (final region in [
                    'ryiadh',
                    'mecca',
                    'medina',
                    'eastern-province',
                    'al-qassim',
                    'asir',
                    'tabuk',
                    'hail',
                    'northern-borders',
                    'jizan',
                    'najran',
                    'al-bahah',
                    'al-jawf',
                  ])
                    DropdownMenuItem(
                      value: region,
                      child: Text(i18n.regionName(region)),
                    ),
                ],
                onChanged: (value) => setState(() => _region = value ?? ''),
              ),
            ),
            for (final entry in _address.entries)
              _Labelled(
                label: i18n.t('factory_${entry.key}'),
                child: TextField(controller: entry.value),
              ),
            const SizedBox(height: 10),
            if (_loadingContent) const LinearProgressIndicator(),
            if (_contentError != null)
              SFStateView(
                message: i18n.t('fc_load_failed'),
                onRetry: _loadContent,
              ),
            if (!_loadingContent && _contentError == null) ...[
              _contentHeading(
                i18n.t('factory_products_title'),
                _products.length,
                _products.length >= 200
                    ? null
                    : () => setState(
                        () => _products.add({
                          'client_key': newUuidV4(),
                          'name': '',
                          'images': <String>[],
                          'tiers': <Map<String, dynamic>>[],
                        }),
                      ),
                i18n.t('factory_add_product'),
              ),
              if (_products.isEmpty) Text(i18n.t('factory_no_products')),
              ..._products.map(_productEditor),
              const SizedBox(height: 18),
              _contentHeading(
                i18n.t('factory_tab_posts'),
                _posts.length,
                _posts.length >= 200
                    ? null
                    : () => setState(
                        () => _posts.add({
                          'client_key': newUuidV4(),
                          'body': '',
                          'image': '',
                          'video': '',
                        }),
                      ),
                i18n.t('factory_add_post'),
              ),
              if (_posts.isEmpty) Text(i18n.t('factory_no_posts')),
              ..._posts.map(_postEditor),
              const SizedBox(height: 20),
            ],
            ElevatedButton(
              onPressed:
                  _saving ||
                      _uploadingWhat != null ||
                      _loadingContent ||
                      _contentError != null
                  ? null
                  : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: SFColors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(i18n.t('btn_update')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentHeading(
    String title,
    int count,
    VoidCallback? add,
    String addLabel,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$title ($count)',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      TextButton.icon(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: Text(addLabel),
      ),
    ],
  );

  Widget _field(
    Map<String, dynamic> item,
    String name,
    String label, {
    int lines = 1,
    bool number = false,
    int? maxLength,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('${item['client_key'] ?? identityHashCode(item)}-$name'),
      initialValue: '${item[name] ?? ''}',
      maxLines: lines,
      maxLength: maxLength,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      decoration: InputDecoration(labelText: context.t(label)),
      onChanged: (value) => item[name] = value,
    ),
  );

  Widget _productEditor(Map<String, dynamic> product) {
    final images = product['images'] as List;
    final tiers = product['tiers'] as List;
    return Card(
      child: ExpansionTile(
        key: ValueKey(product['client_key']),
        initiallyExpanded: (product['name'] ?? '').toString().isEmpty,
        title: Text(
          (product['name'] ?? '').toString().isEmpty
              ? context.t('factory_add_product')
              : product['name'] as String,
        ),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          _field(product, 'name', 'product_name_placeholder', maxLength: 300),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final image in images)
                Stack(
                  children: [
                    SFImage(url: image as String, width: 76, height: 76),
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: IconButton.filledTonal(
                        onPressed: () => setState(() => images.remove(image)),
                        tooltip: context.t('post_remove_media'),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              if (images.length < 5)
                IconButton.outlined(
                  onPressed: _uploadingWhat != null
                      ? null
                      : () => _pickContentImage(product, product: true),
                  tooltip: context.t('product_add_image'),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
            ],
          ),
          if (_uploadingWhat == product['client_key'])
            const LinearProgressIndicator(),
          const SizedBox(height: 14),
          _field(
            product,
            'description',
            'product_description',
            lines: 3,
            maxLength: 2000,
          ),
          _field(product, 'material', 'product_material', maxLength: 120),
          _field(product, 'sizes', 'product_sizes', maxLength: 120),
          _field(product, 'colors', 'product_colors', maxLength: 120),
          _field(product, 'moq', 'product_moq', number: true),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '${context.t('tier_pricing')} (SAR)',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          for (final tier in tiers)
            Row(
              key: ObjectKey(tier),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    tier as Map<String, dynamic>,
                    'min',
                    'tier_from',
                    number: true,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: _field(tier, 'max', 'tier_to', number: true)),
                const SizedBox(width: 6),
                Expanded(
                  child: _field(tier, 'price', 'tier_price', number: true),
                ),
                IconButton(
                  onPressed: () => setState(() => tiers.remove(tier)),
                  tooltip: context.t('tier_remove'),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          Text(
            context.t('tier_hint'),
            style: const TextStyle(fontSize: 12, color: SFColors.muted2),
          ),
          if (tiers.isNotEmpty &&
              tiers.every((tier) => '${tier['max'] ?? ''}'.trim().isNotEmpty))
            Text(
              context.t('tier_gap_warn'),
              style: const TextStyle(fontSize: 12, color: SFColors.danger),
            ),
          TextButton.icon(
            onPressed: tiers.length >= 8
                ? null
                : () => setState(() {
                    int next = 1;
                    for (final tier in tiers) {
                      final last =
                          int.tryParse('${tier['max'] ?? tier['min']}') ?? 0;
                      if (last >= next) next = last + 1;
                    }
                    tiers.add(<String, dynamic>{
                      'min': next,
                      'max': null,
                      'price': '',
                    });
                  }),
            icon: const Icon(Icons.add),
            label: Text(context.t('tier_add')),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _products.remove(product)),
            icon: const Icon(Icons.delete_outline, color: SFColors.danger),
            label: Text(context.t('product_delete')),
          ),
        ],
      ),
    );
  }

  Widget _postEditor(Map<String, dynamic> post) => Card(
    child: ExpansionTile(
      key: ValueKey(post['client_key']),
      initiallyExpanded: '${post['body'] ?? ''}'.isEmpty,
      title: Text(
        '${post['body'] ?? ''}'.isEmpty
            ? context.t('factory_add_post')
            : '${post['body']}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      childrenPadding: const EdgeInsets.all(12),
      children: [
        _field(
          post,
          'body',
          'factory_post_placeholder',
          lines: 4,
          maxLength: 10000,
        ),
        if (safeMediaUrl(post['image']).isNotEmpty)
          SFImage(url: safeMediaUrl(post['image']), height: 160),
        if (safeMediaUrl(post['video']).isNotEmpty)
          const Icon(Icons.videocam_outlined),
        if (_uploadingWhat == post['client_key'])
          const LinearProgressIndicator(),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _uploadingWhat != null
                  ? null
                  : () => _pickPostVideo(post),
              icon: const Icon(Icons.video_call_outlined),
              label: Text(context.t('post_add_video')),
            ),
            TextButton.icon(
              onPressed: _uploadingWhat != null
                  ? null
                  : () => _pickContentImage(post, product: false),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(context.t('post_add_image')),
            ),
            if (safeMediaUrl(post['image']).isNotEmpty ||
                safeMediaUrl(post['video']).isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  post['image'] = '';
                  post['video'] = '';
                }),
                child: Text(context.t('post_remove_media')),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _posts.remove(post)),
              icon: const Icon(Icons.delete_outline, color: SFColors.danger),
              label: Text(context.t('product_delete')),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _pickPostVideo(Map<String, dynamic> post) async {
    setState(() => _uploadingWhat = '${post['client_key']}');
    try {
      final url = await SFUpload.pickAndUploadVideo(
        bucket: SFBuckets.factoryMedia,
        folder: 'posts',
      );
      if (url != null && mounted) setState(() => post['video'] = url);
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _uploadingWhat = null);
    }
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
