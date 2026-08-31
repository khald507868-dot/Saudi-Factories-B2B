// ============================================================
//  الحساب — مقابل app-account.html
//
//  مركز التنقّل: ملفي الشخصي، مصنعي (لحسابات المصانع)،
//  الإعدادات، المساعدة، إدارة المصانع (للمشرفين)، الخروج.
//
//  رابط "مصنعي" يحتاج معرّف المصنع، وهو ما لا يعرفه العميل
//  إلا بسؤال القاعدة عن factories.id بـ owner_id.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/factory_service.dart';
import '../widgets/common.dart';
import 'admin_page.dart';
import 'factory_page.dart';
import 'help_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'splash_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  SFFactory? _myFactory;

  @override
  void initState() {
    super.initState();
    _loadFactory();
  }

  Future<void> _loadFactory() async {
    if (!AuthService.instance.isSignedIn) return;
    try {
      final f = await FactoryService.mine();
      if (!mounted) return;
      setState(() => _myFactory = f);
    } catch (_) {
      // لا مصنع أو تعذّر الاتصال — الرابط ببساطة لا يظهر.
    }
  }

  Future<void> _signOut() async {
    final i18n = context.i18n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(i18n.t('btn_logout')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              i18n.t('btn_logout'),
              style: const TextStyle(color: SFColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final auth = AuthService.instance;
    final profile = auth.profile;

    if (!auth.isSignedIn) {
      return Scaffold(
        backgroundColor: SFColors.pageBg,
        appBar: SFTopBar(title: i18n.t('nav_account')),
        body: SFStateView(
          message: 'يجب تسجيل الدخول',
          icon: Icons.lock_outline,
        ),
      );
    }

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(title: i18n.t('nav_account')),
      body: RefreshIndicator(
        onRefresh: () async {
          await auth.refreshProfile();
          await _loadFactory();
        },
        color: SFColors.midGreen,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // بطاقة المستخدم
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SFColors.darkGreen,
                borderRadius: BorderRadius.circular(SFMetrics.radius),
              ),
              child: Row(
                children: [
                  SFImage(
                    url: profile?.companyImage ?? '',
                    width: 54,
                    height: 54,
                    radius: 999,
                    placeholderIcon: Icons.person_outline,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.fullName?.isNotEmpty == true
                              ? profile!.fullName!
                              : (profile?.email ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SFColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          i18n.t(profile?.isFactory == true
                              ? 'dash_account_factory'
                              : 'dash_account_individual'),
                          style: const TextStyle(
                            color: SFColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            _Row(
              icon: Icons.person_outline,
              label: i18n.t('row_profile'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              ),
            ),
            if (_myFactory != null)
              _Row(
                icon: Icons.factory_outlined,
                label: i18n.t('my_factory'),
                trailing: _myFactory!.isApproved
                    ? null
                    : SFStatusChip(
                        status: _myFactory!.status,
                        label: i18n.t(switch (_myFactory!.status) {
                          'rejected' => 'fs_rejected',
                          _ => 'fs_pending',
                        }),
                      ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FactoryPage(factoryId: _myFactory!.id),
                  ),
                ),
              ),
            _Row(
              icon: Icons.settings_outlined,
              label: i18n.t('row_settings'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
            _Row(
              icon: Icons.help_outline,
              label: i18n.t('row_help'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpPage()),
              ),
            ),
            // لوحة الإدارة — تظهر للمشرف فقط، وليست في أي قائمة تنقّل.
            if (profile?.isAdmin == true)
              _Row(
                icon: Icons.verified_outlined,
                label: i18n.t('dash_admin_factories'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminPage()),
                ),
              ),
            const SizedBox(height: 10),
            _Row(
              icon: Icons.logout,
              label: i18n.t('btn_logout'),
              danger: true,
              onTap: _signOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? SFColors.danger : SFColors.darkGreen;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: SFColors.white,
            border: Border.all(color: SFColors.border),
            borderRadius: BorderRadius.circular(SFMetrics.radius),
          ),
          child: Row(
            children: [
              Icon(icon, size: 21, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              ?trailing,
              if (trailing == null && !danger)
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                  color: SFColors.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
