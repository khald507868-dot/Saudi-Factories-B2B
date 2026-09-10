import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'common.dart';
import 'delivery_address_widgets.dart';
import 'promotion_image_appearance.dart';

/// لون الإعلان في أعلى الصفحة يتحول إلى زجاج أبيض عند التمرير.
class HomeHeader extends StatelessWidget implements PreferredSizeWidget {
  const HomeHeader({
    super.key,
    required this.scrollController,
    required this.promotionColor,
    required this.searchHint,
    required this.onSearchSubmitted,
  });

  static const height = 84.0;

  final ScrollController scrollController;
  final Color promotionColor;
  final String searchHint;
  final ValueChanged<String> onSearchSubmitted;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: scrollController,
    builder: (context, _) {
      final offset = scrollController.hasClients
          ? scrollController.offset
          : 0.0;
      final progress = (offset / 100).clamp(0.0, 1.0);
      final background = Color.lerp(
        promotionColor,
        SFColors.white.withValues(alpha: 0.78),
        progress,
      )!;
      // طبقة بيضاء خفيفة مع التمويه تبقي العنوان مقروءاً فوق المحتوى.
      final foreground = promotionHeaderForeground(
        Color.alphaBlend(background, SFColors.white),
      );

      return ClipRect(
        child: BackdropFilter(
          enabled: progress > 0,
          filter: ui.ImageFilter.blur(
            sigmaX: 12 * progress,
            sigmaY: 12 * progress,
          ),
          child: ColoredBox(
            key: const ValueKey('home-header-background'),
            color: background,
            child: SFTopBar(
              compact: true,
              toolbarHeight: 44,
              backgroundColor: Colors.transparent,
              searchBackgroundColor: SFColors.white.withValues(
                alpha: 1 - 0.12 * progress,
              ),
              showBottomBorder: false,
              titleWidget: DeliveryAddressHeader(foregroundColor: foreground),
              searchHint: searchHint,
              onSearchSubmitted: onSearchSubmitted,
            ),
          ),
        ),
      );
    },
  );
}
