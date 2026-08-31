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
  late final TextEditingController _name =
      TextEditingController(text: widget.factory.name);
  late final TextEditingController _about =
      TextEditingController(text: widget.factory.about);
  late final TextEditingController _website =
      TextEditingController(text: widget.factory.website);
  late final TextEditingController _companySize =
      TextEditingController(text: widget.factory.companySize);

  late String _cover = widget.factory.cover;
  late String _logo = widget.factory.logo;
  late String _industry = widget.factory.industry;

  bool _saving = false;
  String? _uploadingWhat;

  @override
  void dispose() {
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
    final website = _website.text.trim();
    // الخادم يرفض رابطاً لا يبدأ بـ http/https، فنمنعه مبكراً
    // برسالة مفهومة بدل خطأ قاعدة بيانات.
    if (website.isNotEmpty &&
        !website.startsWith('http://') &&
        !website.startsWith('https://')) {
      showSFError(
        context,
        Exception('الموقع الإلكتروني يجب أن يبدأ بـ http:// أو https://'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await FactoryService.save(
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
        expectedUpdatedAt: widget.factory.updatedAt,
      );
      if (!mounted) return;
      showSFMessage(context, context.t('saved_msg'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      showSFError(
        context,
        msg.contains('40001')
            ? Exception('عُدِّلت بيانات المصنع في جلسة أخرى — أعد فتح الصفحة')
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
      body: ListView(
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
                  const Icon(Icons.camera_alt_outlined,
                      color: SFColors.white, size: 28),
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
              initialValue: _industry.isEmpty ? null : _industry,
              isExpanded: true,
              items: cats
                  .map((c) => DropdownMenuItem(
                        value: i18n.categoryKey(c),
                        child: Text(
                          i18n.categoryName(c),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
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

          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _saving ? null : _save,
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
    );
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
