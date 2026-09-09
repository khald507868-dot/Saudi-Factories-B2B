import 'package:flutter/material.dart';

/// يعرض رمز الريال برسم الويب نفسه، دون الاعتماد على محرف لا يدعمه الخط.
class SFPriceText extends StatelessWidget {
  const SFPriceText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.textDirection = TextDirection.ltr,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    final size = MediaQuery.textScalerOf(context)
        .scale(resolved.fontSize ?? 14);
    final parts = text.split('﷼');
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: CustomPaint(
                    size: Size(size * 1.04, size * .96),
                    painter: _RiyalPainter(
                      resolved.color ?? const Color(0xFF04361B),
                    ),
                  ),
                ),
              ),
            TextSpan(text: parts[i]),
          ],
        ],
      ),
      semanticsLabel: text.replaceAll('﷼', 'SAR'),
      style: style,
      textAlign: textAlign,
      textDirection: textDirection,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// المسارات من SVG الموجود في green-frames.css (viewBox 1080 × 1000).
class _RiyalPainter extends CustomPainter {
  const _RiyalPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1080, size.height / 1000);
    final paint = Paint()..color = color;
    final left = Path()
      ..moveTo(556, 60)
      ..relativeCubicTo(-45, 30, -83, 66, -112, 108)
      ..relativeLineTo(0, 366)
      ..relativeLineTo(-134, 29)
      ..relativeCubicTo(-16, 38, -27, 79, -33, 122)
      ..relativeLineTo(167, -36)
      ..relativeLineTo(0, 128)
      ..relativeLineTo(-232, 50)
      ..relativeCubicTo(-16, 38, -27, 79, -33, 122)
      ..relativeLineTo(286, -62)
      ..relativeCubicTo(34, -7, 63, -28, 81, -57)
      ..relativeLineTo(43, -69)
      ..lineTo(589, 60)
      ..close();
    final right = Path()
      ..moveTo(770, 104)
      ..relativeCubicTo(-38, 27, -71, 57, -97, 90)
      ..relativeLineTo(0, 306)
      ..relativeLineTo(-88, 19)
      ..relativeLineTo(0, 106)
      ..relativeLineTo(88, -19)
      ..relativeLineTo(0, 128)
      ..relativeLineTo(253, -55)
      ..relativeCubicTo(16, -38, 27, -79, 33, -122)
      ..relativeLineTo(-181, 39)
      ..relativeLineTo(0, -106)
      ..relativeLineTo(181, -39)
      ..relativeCubicTo(16, -38, 27, -79, 33, -122)
      ..relativeLineTo(-222, 48)
      ..lineTo(770, 104)
      ..close();
    final base = Path()
      ..moveTo(676, 800)
      ..relativeCubicTo(-16, 38, -27, 79, -33, 122)
      ..relativeLineTo(286, -62)
      ..relativeCubicTo(16, -38, 27, -79, 33, -122)
      ..relativeLineTo(-286, 62)
      ..close();
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
    canvas.drawPath(base, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RiyalPainter oldDelegate) => oldDelegate.color != color;
}
