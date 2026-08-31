// ============================================================
//  إدارة المصانع — مقابل app-admin.html
//
//  محجوبة بـ is_admin، وليست في أي قائمة تنقّل.
//
//  تنبيه مهم مأخوذ من علّة شحنت في نسخة الويب: قيمة الحالة
//  المسموحة هي "approved" لا "approve". إرسال الثانية يرفضه
//  القيد factories_status_check، ويبدو الخطأ وكأنه مشكلة
//  صلاحيات وليس قيمة. الحارس في FactoryService.setStatus.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/factory_service.dart';
import '../widgets/common.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late Future<List<SFFactory>> _future;

  @override
  void initState() {
    super.initState();
    _future = FactoryService.pending();
  }

  Future<void> _reload() async {
    setState(() => _future = FactoryService.pending());
    await _future;
  }

  Future<void> _setStatus(SFFactory f, String status) async {
    try {
      await FactoryService.setStatus(f.id, status);
      if (!mounted) return;
      showSFMessage(context, context.t('saved_msg'));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      // نعرض نصّ الخطأ كما هو: رسالة القاعدة تسمّي السبب
      // الحقيقي (قيد مرفوض، صلاحية مرفوضة) في سطر واحد.
      showSFError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    // الحجب هنا للواجهة؛ الحماية الحقيقية في سياسات الخادم.
    if (AuthService.instance.profile?.isAdmin != true) {
      return Scaffold(
        appBar: AppBar(title: Text(i18n.t('admin_page_title'))),
        body: const SFStateView(
          message: 'هذه الصفحة للمشرفين فقط',
          icon: Icons.lock_outline,
        ),
      );
    }

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(title: Text(i18n.t('admin_page_title'))),
      body: RefreshIndicator(
        onRefresh: _reload,
        color: SFColors.midGreen,
        child: FutureBuilder<List<SFFactory>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return SFStateView(
                message: i18n.t('fx_loading'),
                loading: true,
              );
            }
            if (snap.hasError) {
              return SFStateView(
                message: i18n.t('fx_failed'),
                icon: Icons.cloud_off,
                onRetry: _reload,
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 90),
                  SFStateView(
                    message: i18n.t('fx_empty'),
                    icon: Icons.verified_outlined,
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final f = items[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SFColors.white,
                    border: Border.all(color: SFColors.border),
                    borderRadius: BorderRadius.circular(SFMetrics.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SFImage(
                            url: f.logo,
                            width: 44,
                            height: 44,
                            radius: 8,
                            placeholderIcon: Icons.factory_outlined,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.name.isEmpty ? '—' : f.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (f.industry.isNotEmpty)
                                  Text(
                                    f.industry,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: SFColors.muted2,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SFStatusChip(
                            status: f.status,
                            label: i18n.t('fs_pending'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              // القيمة "approved" — لا "approve".
                              onPressed: () => _setStatus(f, 'approved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SFColors.midGreen,
                                minimumSize: const Size.fromHeight(42),
                              ),
                              child: Text(i18n.t('fs_approved')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _setStatus(f, 'rejected'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: SFColors.danger,
                                side: const BorderSide(
                                    color: SFColors.danger),
                                minimumSize: const Size.fromHeight(42),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      SFMetrics.radius),
                                ),
                              ),
                              child: Text(i18n.t('fs_rejected')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
