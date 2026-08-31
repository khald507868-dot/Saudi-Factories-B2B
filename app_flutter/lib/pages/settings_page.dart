// ============================================================
//  الإعدادات — مقابل app-settings.html
//
//  منتقي اللغة هو جوهر الصفحة: ثلاثون لغة، وأعلامها تُولَّد
//  من رمز الدولة بحساب أحرف المؤشّر الإقليمي — لا صور أعلام.
//
//  تغيير اللغة في الويب كان يُعيد تحميل الصفحة؛ هنا تُبنى
//  الواجهة من جديد وحدها، والاتجاه يتبعها.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/i18n_data.dart';
import '../core/theme.dart';

/// اللغة ← (الاسم بلغتها، رمز الدولة للعلم).
/// لا تُدرِج رمزاً لا يوجد في jدول الترجمة — سيظهر بالإنجليزية
/// ويبدو معطوباً.
const Map<String, List<String>> kLanguagePicker = {
  'ar': ['العربية', 'SA'],
  'en': ['English', 'GB'],
  'fr': ['Français', 'FR'],
  'es': ['Español', 'ES'],
  'de': ['Deutsch', 'DE'],
  'it': ['Italiano', 'IT'],
  'pt': ['Português', 'PT'],
  'ru': ['Русский', 'RU'],
  'tr': ['Türkçe', 'TR'],
  'fa': ['فارسی', 'IR'],
  'ur': ['اردو', 'PK'],
  'hi': ['हिन्दी', 'IN'],
  'zh': ['中文', 'CN'],
  'ja': ['日本語', 'JP'],
  'ko': ['한국어', 'KR'],
  'id': ['Indonesia', 'ID'],
  'ms': ['Melayu', 'MY'],
  'th': ['ไทย', 'TH'],
  'vi': ['Tiếng Việt', 'VN'],
  'he': ['עברית', 'IL'],
  'nl': ['Nederlands', 'NL'],
  'pl': ['Polski', 'PL'],
  'sv': ['Svenska', 'SE'],
  'el': ['Ελληνικά', 'GR'],
  'bn': ['বাংলা', 'BD'],
  'pa': ['ਪੰਜਾਬੀ', 'IN'],
  'ta': ['தமிழ்', 'IN'],
  'sw': ['Kiswahili', 'KE'],
  'am': ['አማርኛ', 'ET'],
  'ku': ['Kurdî', 'IQ'],
};

/// يبني رمز العلم من حرفي رمز الدولة — نفس حساب نسخة الويب.
String flagEmoji(String countryCode) {
  const base = 127397;
  return countryCode
      .toUpperCase()
      .codeUnits
      .map((c) => String.fromCharCode(base + c))
      .join();
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final current = kLanguagePicker[i18n.lang];

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(title: Text(i18n.t('row_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            i18n.t('section_preferences'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: SFColors.muted2,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _pickLanguage(context),
            borderRadius: BorderRadius.circular(SFMetrics.radius),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                color: SFColors.white,
                border: Border.all(color: SFColors.border),
                borderRadius: BorderRadius.circular(SFMetrics.radius),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language, color: SFColors.darkGreen),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      i18n.t('row_language'),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (current != null)
                    Text(
                      '${flagEmoji(current[1])}  ${current[0]}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: SFColors.muted2,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            i18n.t('section_other'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: SFColors.muted2,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SFColors.white,
              border: Border.all(color: SFColors.border),
              borderRadius: BorderRadius.circular(SFMetrics.radius),
            ),
            child: Row(
              children: [
                Text(
                  i18n.t('app_version'),
                  style: const TextStyle(fontSize: 14),
                ),
                const Spacer(),
                const Text(
                  '1.0.0',
                  style: TextStyle(fontSize: 13, color: SFColors.muted2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ورقة سفلية بقائمة اللغات وبحث — نفس نمط النسخة القديمة.
  void _pickLanguage(BuildContext context) {
    final i18n = context.i18n;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SFColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _LanguageSheet(current: i18n.lang),
    );
  }
}

class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.current});

  final String current;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    final entries = kLanguagePicker.entries.where((e) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.value[0].toLowerCase().contains(q) ||
          e.key.contains(q);
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: SFColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    i18n.t('row_language'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '...',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final selected = e.key == widget.current;
                return ListTile(
                  leading: Text(
                    flagEmoji(e.value[1]),
                    style: const TextStyle(fontSize: 22),
                  ),
                  title: Text(
                    e.value[0],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check, color: SFColors.green)
                      : null,
                  onTap: () async {
                    await i18n.setLang(e.key);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// حارس بسيط: يمنع إدراج لغة في المنتقي بلا ترجمة في الجدول.
/// يُشغَّل في وضع التطوير فقط.
bool languagePickerIsConsistent() {
  for (final code in kLanguagePicker.keys) {
    if (!kDict.containsKey(code)) return false;
  }
  return true;
}
