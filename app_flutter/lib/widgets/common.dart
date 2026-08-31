// ============================================================
//  عناصر واجهة مشتركة صغيرة
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// شريط علوي بالأخضر الداكن مع مربّع بحث — مقابل .top-bar.
class SFTopBar extends StatelessWidget implements PreferredSizeWidget {
  const SFTopBar({
    super.key,
    this.title,
    this.searchHint,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.actions,
    this.leading,
    this.showBack = false,
  });

  final String? title;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final List<Widget>? actions;
  final Widget? leading;

  /// زر الرجوع موجود في مسار التطبيق (خلافاً لصفحات الويب).
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(SFMetrics.topBarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: showBack,
      leading: leading,
      titleSpacing: 12,
      title: searchHint != null
          ? _SearchField(
              hint: searchHint!,
              onChanged: onSearchChanged,
              onSubmitted: onSearchSubmitted,
            )
          : Text(
              title ?? '',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: SFColors.white,
              ),
            ),
      actions: actions,
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.hint,
    this.onChanged,
    this.onSubmitted,
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: SFColors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: SFColors.darkGreen),
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
                hintStyle: const TextStyle(
                  fontSize: 15,
                  color: SFColors.muted,
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
              Icon(icon ?? Icons.inbox_outlined,
                  size: 48, color: SFColors.muted),
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
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
