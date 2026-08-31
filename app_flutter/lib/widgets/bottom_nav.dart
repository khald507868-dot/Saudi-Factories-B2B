// ============================================================
//  الشريط السفلي — ستة عناصر بنفس ترتيب نسخة الويب
//
//  في الويب كان هذا الشريط مكرّراً في عشرة ملفات وارتفاعه
//  (52 بكسل) مكرّراً في ثلاثة عشر موضعاً. هنا هو widget واحد،
//  فتعديله مرّة واحدة يكفي.
//
//  شارة الرسائل غير المقروءة تُقرأ من get_unread_message_total
//  وتتحدّث مع كل تغيّر في جدول الرسائل.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// أقسام الشريط السفلي.
enum SFTab { home, categories, factories, messages, account, cart }

class SFBottomNav extends StatelessWidget {
  const SFBottomNav({
    super.key,
    required this.current,
    required this.onTap,
    this.unreadMessages = 0,
    this.cartCount = 0,
  });

  final SFTab current;
  final ValueChanged<SFTab> onTap;
  final int unreadMessages;
  final int cartCount;

  static const _items = <(SFTab, IconData, String)>[
    (SFTab.home, Icons.home_outlined, 'nav_home'),
    (SFTab.categories, Icons.grid_view_outlined, 'nav_categories'),
    (SFTab.factories, Icons.factory_outlined, 'nav_factories'),
    (SFTab.messages, Icons.chat_bubble_outline, 'nav_messages'),
    (SFTab.account, Icons.person_outline, 'nav_account'),
    (SFTab.cart, Icons.shopping_cart_outlined, 'nav_cart'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      height: SFMetrics.bottomNavHeight + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: SFColors.darkGreen,
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: _items.map((item) {
          final (tab, icon, key) = item;
          final active = tab == current;
          final badge = switch (tab) {
            SFTab.messages => unreadMessages,
            SFTab.cart => cartCount,
            _ => 0,
          };

          return Expanded(
            child: InkWell(
              onTap: () => onTap(tab),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        icon,
                        size: 21,
                        color: active ? SFColors.green : SFColors.white,
                      ),
                      if (badge > 0)
                        PositionedDirectional(
                          // يتبع اتجاه اللغة تلقائياً — لا حاجة لنسخة ltr.
                          start: -8,
                          top: -5,
                          child: _Badge(count: badge),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t(key),
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? SFColors.green : SFColors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: SFColors.danger,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: SFColors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
