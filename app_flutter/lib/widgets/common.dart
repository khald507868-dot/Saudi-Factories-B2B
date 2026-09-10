// ============================================================
//  عناصر واجهة مشتركة صغيرة
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/i18n.dart';

/// شريط أبيض مثل الويب؛ البحث في سطر مستقل كي لا يزاحم الشعار.
class SFTopBar extends StatelessWidget implements PreferredSizeWidget {
  const SFTopBar({
    super.key,
    this.title,
    this.titleWidget,
    this.searchHint,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.actions,
    this.leading,
    this.showBack = false,
    this.compact = false,
    this.toolbarHeight,
  });

  final String? title;
  final Widget? titleWidget;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final List<Widget>? actions;
  final Widget? leading;
  final bool compact;
  final double? toolbarHeight;

  double get _toolbarHeight =>
      toolbarHeight ?? (compact ? 40 : SFMetrics.topBarHeight);
  double get _searchHeight => compact ? 34 : 44;
  double get _searchBottomPadding => compact ? 6 : 16;

  /// زر الرجوع موجود في مسار التطبيق (خلافاً لصفحات الويب).
  final bool showBack;

  @override
  Size get preferredSize => Size.fromHeight(
    _toolbarHeight +
        (searchHint == null ? 0 : _searchHeight + _searchBottomPadding),
  );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: _toolbarHeight,
      automaticallyImplyLeading: showBack,
      leading: leading,
      titleSpacing: 16,
      title:
          titleWidget ??
          Text(
            title ?? context.t('app_title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: SFColors.darkGreen,
            ),
          ),
      actions: [
        ...?actions,
        if (actions?.isNotEmpty ?? false) const SizedBox(width: 12),
      ],
      bottom: searchHint == null
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(
                _searchHeight + _searchBottomPadding,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, _searchBottomPadding),
                child: _SearchField(
                  compact: compact,
                  hint: searchHint!,
                  onChanged: onSearchChanged,
                  onSubmitted: onSearchSubmitted,
                ),
              ),
            ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.compact = false,
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 34 : 44,
      decoration: BoxDecoration(
        color: SFColors.surfaceAlt,
        border: Border.all(color: SFColors.searchBorder),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: compact ? 18 : 20,
            color: SFColors.darkGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                // 16 بكسل حدّاً أدنى: أقل من ذلك يجعل بعض الأجهزة
                // تكبّر الشاشة تلقائياً عند التركيز على الحقل.
                fontSize: 16,
                color: SFColors.darkGreen,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: compact ? 12 : 14,
                  color: SFColors.muted2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة فارغة/خطأ/تحميل موحّدة — مقابل showState() في الويب.
class SFStateView extends StatelessWidget {
  const SFStateView({
    super.key,
    required this.message,
    this.icon,
    this.loading = false,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator(color: SFColors.green)
            else
              Icon(
                icon ?? Icons.inbox_outlined,
                size: 48,
                color: SFColors.muted,
              ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: SFColors.muted2,
                height: 1.6,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(retryLabel ?? '↻'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// صورة من الشبكة مع بديل عند غيابها أو فشلها.
class SFImage extends StatelessWidget {
  const SFImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.radius = SFMetrics.radius,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image_outlined,
  });

  final String url;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: width,
      height: height,
      color: SFColors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, color: SFColors.muted, size: 28),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: width,
                  height: height,
                  color: SFColors.surfaceAlt,
                );
              },
            ),
    );
  }
}

/// شارة حالة المصنع (قيد المراجعة / معتمد / مرفوض).
class SFStatusChip extends StatelessWidget {
  const SFStatusChip({super.key, required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'approved' => (const Color(0xFFEAF3EE), SFColors.midGreen),
      'rejected' => (SFColors.dangerBg, SFColors.danger),
      _ => (const Color(0xFFFFF6E0), const Color(0xFF8A6D00)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// يعرض رسالة خطأ بالعربية أسفل الشاشة.
void showSFError(BuildContext context, Object error) {
  final text = error is Exception
      ? error.toString().replaceFirst('Exception: ', '')
      : '$error';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: SFColors.danger,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// يعرض رسالة نجاح.
void showSFMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: SFColors.midGreen,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
