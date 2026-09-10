// ============================================================
//  شريط عائم بحواف دائرية ومؤشر متحرك يشمل الأيقونة واسم القسم.
//
//  شارة الرسائل غير المقروءة تُقرأ من get_unread_message_total
//  وتتحدّث مع كل تغيّر في جدول الرسائل.
// ============================================================

import 'dart:ui' show ImageFilter;

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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 4, 18, 6 + bottomInset),
      child: Center(
        heightFactor: 1,
        child: SizedBox(
          key: const ValueKey('sf-bottom-nav-surface'),
          width: double.infinity,
          height: SFMetrics.bottomNavHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: SFColors.darkGreen.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        SFColors.surfaceAlt.withValues(alpha: 0.98),
                        SFColors.surfaceAlt.withValues(alpha: 0.94),
                        SFColors.surfaceAlt.withValues(alpha: 0.92),
                      ],
                    ),
                    border: Border.all(
                      color: SFColors.white.withValues(alpha: 0.95),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemWidth = constraints.maxWidth / _items.length;
                        return Stack(
                          children: [
                            AnimatedPositionedDirectional(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              start: SFTab.values.indexOf(current) * itemWidth,
                              top: 0,
                              bottom: 0,
                              width: itemWidth,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      SFColors.selected,
                                      SFColors.border,
                                    ],
                                  ),
                                  border: Border.all(
                                    color: SFColors.white,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _items.map((item) {
                                final (tab, icon, key) = item;
                                final badge = switch (tab) {
                                  SFTab.messages => unreadMessages,
                                  SFTab.cart => cartCount,
                                  _ => 0,
                                };
                                return Expanded(
                                  child: _buildItem(
                                    context,
                                    tab,
                                    icon,
                                    key,
                                    badge,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    SFTab tab,
    IconData icon,
    String key,
    int badge,
  ) {
    final active = tab == current;
    return Semantics(
      selected: active,
      button: true,
      label: context.t(key),
      value: badge > 0 ? '$badge' : null,
      excludeSemantics: true,
      onTap: () => onTap(tab),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onTap(tab),
          borderRadius: BorderRadius.circular(999),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 28,
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 20, color: SFColors.darkGreen),
                    if (badge > 0)
                      PositionedDirectional(
                        end: 1,
                        top: -2,
                        child: IgnorePointer(child: _Badge(count: badge)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Text(
                context.t(tab == SFTab.cart ? 'nav_cart_short' : key),
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: SFColors.darkGreen,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
      constraints: const BoxConstraints(minWidth: 14),
      height: 14,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: SFColors.danger,
        border: Border.all(color: SFColors.white, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textDirection: TextDirection.ltr,
        style: const TextStyle(
          color: SFColors.white,
          fontSize: 7.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
