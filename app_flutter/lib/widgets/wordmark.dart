// ============================================================
//  الشعار الكتابي — "مصانع السعودية B2B"
//
//  الاسم لاتيني دائماً فيُثبَّت اتجاهه (ltr) حتى لا ينعكس
//  ترتيب الكلمتين في العربية. و"B2B" ذهبية ومرفوعة قليلاً.
//  لا يوجد ملف صورة في المشروع — الشعار مبني بالنص والرسم.
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme.dart';

class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.fontSize = 11,
    this.width = 108,
    this.onDark = true,
  });

  final double fontSize;
  final double width;

  /// على خلفية داكنة يصير "السعودية" أبيض؛ وإلا أخضر داكن.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  height: 1.55, // يترك مجالاً لـ B2B المرفوعة
                ),
                children: [
                  const TextSpan(
                    text: 'Saudi ',
                    style: TextStyle(color: SFColors.green),
                  ),
                  TextSpan(
                    text: 'Factories',
                    style: TextStyle(
                      color: onDark ? SFColors.white : SFColors.darkGreen,
                    ),
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.top,
                    child: Transform.translate(
                      offset: const Offset(1, -1),
                      child: Text(
                        'B2B',
                        style: TextStyle(
                          fontSize: fontSize * 0.62,
                          fontWeight: FontWeight.w800,
                          color: SFColors.gold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          ),
          const SizedBox(height: 2),
          // الخط المتدرّج تحت الاسم — يتبع اتجاه اللغة.
          Container(
            height: 1.5,
            width: width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Directionality.of(context) == TextDirection.rtl
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                end: Directionality.of(context) == TextDirection.rtl
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                colors: const [
                  SFColors.midGreen,
                  SFColors.green,
                  SFColors.gold,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
