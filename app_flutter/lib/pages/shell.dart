// ============================================================
//  الهيكل الرئيسي — يستضيف أقسام الشريط السفلي
//
//  في نسخة الويب كان كل قسم صفحة HTML مستقلة وكان الشريط
//  السفلي مكرّراً في عشرة ملفات. هنا قسم واحد يتبدّل داخله،
//  فتُحفظ حالة كل تبويب ولا يُعاد تحميله عند كل تنقّل.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/commerce_service.dart';
import '../services/messages_service.dart';
import '../widgets/bottom_nav.dart';
import 'account_page.dart';
import 'cart_page.dart';
import 'categories_page.dart';
import 'factories_page.dart';
import 'home_page.dart';
import 'messages_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = SFTab.home});

  final SFTab initialTab;

  @override
  State<AppShell> createState() => AppShellState();

  /// يتيح لأي شاشة داخلية أن تنتقل إلى تبويب آخر.
  static AppShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();

  /// المسارات المدفوعة تكون أشقاء لمسار الهيكل لا أبناءً له، ولذلك لا يستطيع
  /// [of] الوصول إلى الهيكل من صفحة تفاصيل منتج مثلاً.
  static AppShellState? get active => AppShellState._active;
}

class AppShellState extends State<AppShell> {
  static AppShellState? _active;

  late SFTab _tab = widget.initialTab;

  int _unread = 0;
  int _cartCount = 0;
  RealtimeChannel? _channel;
  GlobalKey<CartPageState> _cartKey = GlobalKey<CartPageState>();
  String? _sessionUser;
  int _counterRequest = 0;

  @override
  void initState() {
    super.initState();
    _active = this;
    _sessionUser = AuthService.instance.user?.id;
    AuthService.instance.addListener(_authChanged);
    _refreshCounters();
    // الشارة تتحدّث مع كل تغيّر في جدول الرسائل — مقابل
    // messages-badge.js الذي كان يُحقن في 19 صفحة.
    _channel = SFMessages.subscribe((_) => _refreshCounters());
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_authChanged);
    if (identical(_active, this)) _active = null;
    if (_channel != null) {
      // ignore: discarded_futures
      _channel!.unsubscribe();
    }
    super.dispose();
  }

  void _authChanged() {
    final user = AuthService.instance.user?.id;
    if (user == _sessionUser || !mounted) return;
    _counterRequest++;
    _sessionUser = user;
    if (_channel != null) unawaited(_channel!.unsubscribe());
    _channel = SFMessages.subscribe((_) => _refreshCounters());
    setState(() {
      _unread = 0;
      _cartCount = 0;
      // مفتاح جديد يمنع نقل حالة سلة الحساب السابق إلى الشجرة الجديدة.
      _cartKey = GlobalKey<CartPageState>();
    });
    unawaited(_refreshCounters());
  }

  /// تُستدعى من الشاشات بعد أي تغيير يمسّ العدّادات.
  Future<void> _refreshCounters() async {
    final request = ++_counterRequest;
    if (!AuthService.instance.isSignedIn) {
      if (mounted) {
        setState(() {
          _unread = 0;
          _cartCount = 0;
        });
      }
      return;
    }
    final unread = await SFMessages.unreadTotal();
    var count = 0;
    try {
      final items = await SFCommerce.loadCart();
      count = items.fold<int>(0, (sum, i) => sum + i.quantity);
    } catch (_) {
      // السلة اختيارية هنا — لا نُفشل الشريط بسببها.
    }
    if (!mounted || request != _counterRequest) return;
    setState(() {
      _unread = unread;
      _cartCount = count;
    });
  }

  void refreshCounters() => unawaited(_refreshCounters());

  void goTo(SFTab tab) {
    if (!mounted) return;
    setState(() => _tab = tab);
    if (tab == SFTab.cart) {
      unawaited(_cartKey.currentState?.refresh() ?? Future<void>.value());
    }
    if (tab == SFTab.messages || tab == SFTab.cart) refreshCounters();
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack يحفظ حالة كل تبويب (موضع التمرير، نتائج البحث).
    final index = SFTab.values.indexOf(_tab);

    return Scaffold(
      body: IndexedStack(
        key: ValueKey(_sessionUser),
        index: index,
        children: [
          const HomePage(),
          const CategoriesPage(),
          const FactoriesPage(),
          const MessagesPage(),
          const AccountPage(),
          CartPage(key: _cartKey),
        ],
      ),
      bottomNavigationBar: SFBottomNav(
        current: _tab,
        unreadMessages: _unread,
        cartCount: _cartCount,
        onTap: goTo,
      ),
    );
  }
}
