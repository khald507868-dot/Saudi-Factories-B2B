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
import 'package:intl/intl.dart' show DateFormat;

import '../core/currency.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/factory_service.dart';
import '../services/messages_service.dart';
import '../services/orders_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common.dart';
import '../widgets/price_text.dart';
import 'auth_page.dart';
import 'admin_page.dart';
import 'factory_page.dart';
import 'favorites_page.dart';
import 'help_page.dart';
import 'profile_page.dart';
import 'invoices_page.dart';
import 'orders_page.dart';
import 'settings_page.dart';
import 'shell.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  SFFactory? _myFactory;
  SFSellerStats? _stats;
  bool _statsLoading = true;
  bool _statsError = false;
  int _unread = 0;
  int _loadSerial = 0;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = AuthService.instance.user?.id;
    AuthService.instance.addListener(_authChanged);
    _loadOverview();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_authChanged);
    super.dispose();
  }

  void _authChanged() {
    final id = AuthService.instance.user?.id;
    if (id != _userId) {
      _userId = id;
      _loadSerial++;
      _myFactory = null;
      _stats = null;
      _unread = 0;
      _loadOverview();
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadOverview() async {
    if (!AuthService.instance.isSignedIn) return;
    final serial = ++_loadSerial;
    if (mounted) setState(() => _statsLoading = true);
    final seller = AuthService.instance.profile?.isFactory == true;
    try {
      final results = await Future.wait([
        FactoryService.mine(),
        SFMessages.unreadTotal(),
        if (seller)
          SFOrders.ownedFactoryIds().then(
            (ids) => SFOrders.load(factoryIds: ids),
          ),
      ]);
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _myFactory = results[0] as SFFactory?;
        _unread = results[1] as int;
        _stats = seller
            ? SFSellerStats.fromOrders(results[2] as List<SFOrder>)
            : null;
        _statsError = false;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _statsError = true;
        _statsLoading = false;
      });
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _loadOverview();
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
            child: Text(i18n.t('msg_cancel')),
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

    try {
      await AuthService.instance.signOut();
    } catch (error) {
      if (mounted) showSFError(context, error);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppShell()),
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
          message: i18n.t('login_required_action'),
          icon: Icons.lock_outline,
          retryLabel: context.t('splash_login_btn'),
          onRetry: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AuthPage(accountType: 'individual'),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(title: i18n.t('nav_account')),
      body: RefreshIndicator(
        onRefresh: () async {
          await auth.refreshProfile();
          await _loadOverview();
        },
        color: SFColors.midGreen,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // بطاقة المستخدم
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SFColors.white,
                border: Border.all(color: SFColors.border),
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
                            color: SFColors.darkGreen,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          i18n.t(
                            profile?.isFactory == true
                                ? 'dash_account_factory'
                                : 'dash_account_individual',
                          ),
                          style: const TextStyle(
                            color: SFColors.muted2,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: i18n.t('row_profile'),
                    onPressed: () => _open(const ProfilePage()),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: SFColors.midGreen,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (profile?.isFactory == true) ...[
              if (_statsLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_statsError)
                SFStateView(
                  message: i18n.t('app_load_error'),
                  onRetry: _loadOverview,
                  retryLabel: i18n.t('app_retry'),
                ),
              if (_stats != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _SellerOverview(stats: _stats!),
                ),
            ],

            _MenuSection(
              title: i18n.t('dash_orders'),
              children: [
                _Row(
                  icon: Icons.inventory_2_outlined,
                  label: i18n.t('dash_my_orders'),
                  onTap: () => _open(const OrdersPage()),
                ),
                if (profile?.isFactory == true) ...[
                  _Row(
                    icon: Icons.task_alt,
                    label: i18n.t('dash_orders_paid'),
                    onTap: () =>
                        _open(const OrdersPage(initialView: OrderView.paid)),
                  ),
                  _Row(
                    icon: Icons.schedule,
                    label: i18n.t('dash_orders_unpaid'),
                    onTap: () =>
                        _open(const OrdersPage(initialView: OrderView.unpaid)),
                  ),
                ],
                _Row(
                  icon: Icons.favorite_border,
                  label: i18n.t('dash_favorites'),
                  onTap: () => _open(const FavoritesPage()),
                ),
                _Row(
                  icon: Icons.receipt_long_outlined,
                  label: i18n.t('row_invoices'),
                  onTap: () => _open(const InvoicesPage()),
                ),
                _Row(
                  icon: Icons.shopping_cart_outlined,
                  label: i18n.t('dash_cart'),
                  onTap: () => AppShell.active?.goTo(SFTab.cart),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MenuSection(
              title: i18n.t('nav_account'),
              children: [
                _Row(
                  icon: Icons.person_outline,
                  label: i18n.t('row_profile'),
                  onTap: () => _open(const ProfilePage()),
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
                    onTap: () => _open(FactoryPage(factoryId: _myFactory!.id)),
                  ),
                _Row(
                  icon: Icons.settings_outlined,
                  label: i18n.t('row_settings'),
                  onTap: () => _open(const SettingsPage()),
                ),
                if (profile?.isAdmin == true)
                  _Row(
                    icon: Icons.verified_outlined,
                    label: i18n.t('dash_admin_factories'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminPage()),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _MenuSection(
              title: i18n.t('app_contact_support'),
              children: [
                _Row(
                  icon: Icons.mail_outline,
                  label: i18n.t('dash_inbox'),
                  trailing: _unread == 0
                      ? null
                      : Badge(
                          label: Text(_unread > 99 ? '99+' : '$_unread'),
                          backgroundColor: SFColors.midGreen,
                        ),
                  onTap: () => AppShell.active?.goTo(SFTab.messages),
                ),
                _Row(
                  icon: Icons.help_outline,
                  label: i18n.t('row_help'),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const HelpPage())),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MenuSection(
              children: [
                _Row(
                  icon: Icons.logout,
                  label: i18n.t('btn_logout'),
                  danger: true,
                  onTap: _signOut,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerOverview extends StatelessWidget {
  const _SellerOverview({required this.stats});
  final SFSellerStats stats;
  @override
  Widget build(BuildContext context) {
    final peak = stats.days.fold<double>(
      0,
      (value, day) => day.total > value ? day.total : value,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final metrics = <String, String>{
                  'dash_stat_paid_total': SFCurrency.formatSar(stats.paidTotal),
                  'dash_stat_pending': SFCurrency.formatSar(stats.pendingTotal),
                  'dash_stat_paid_orders': '${stats.paidCount}',
                };
                final columns = constraints.maxWidth < 290 ? 2 : 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  children: [
                    for (final entry in metrics.entries)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 8) /
                            columns,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SFPriceText(
                              entry.value,
                              textAlign:
                                  Directionality.of(context) ==
                                      TextDirection.rtl
                                  ? TextAlign.right
                                  : TextAlign.left,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: SFColors.midGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.t(entry.key),
                              style: const TextStyle(
                                fontSize: 12,
                                color: SFColors.muted2,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const Divider(height: 24),
            Text(
              context.t('dash_chart_title'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (peak == 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SFColors.pageBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.show_chart,
                      color: SFColors.softGreen,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.t('dash_chart_no_revenue'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: SFColors.muted2,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              SizedBox(
                height: 64,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in stats.days)
                      Expanded(
                        child: Tooltip(
                          message:
                              '${DateFormat('dd/MM').format(day.day)}: ${SFCurrency.formatSar(day.total)}',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Container(
                              height: (day.total / peak * 64).clamp(2, 64),
                              color: day.total == 0
                                  ? SFColors.border
                                  : SFColors.midGreen,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('dd/MM').format(stats.days.first.day),
                    style: const TextStyle(
                      fontSize: 11,
                      color: SFColors.muted2,
                    ),
                  ),
                  Text(
                    DateFormat('dd/MM').format(stats.days.last.day),
                    style: const TextStyle(
                      fontSize: 11,
                      color: SFColors.muted2,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text(
              title!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SFColors.muted2,
              ),
            ),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 52, end: 14),
                    child: Divider(height: 1, color: Color(0xFFE6EBE8)),
                  ),
                children[index],
              ],
            ],
          ),
        ),
      ],
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

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? color : SFColors.midGreen),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (trailing != null) Flexible(child: trailing!),
            if (!danger) ...[
              const SizedBox(width: 6),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                color: SFColors.muted2,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
