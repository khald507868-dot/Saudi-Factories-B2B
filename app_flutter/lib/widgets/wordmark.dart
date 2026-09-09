import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'wordmark_paths.dart';

/// The web wordmark's Segoe UI Black lettering, preserved as vector outlines
/// so the brand keeps its shape on every platform and in every locale.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.fontSize = 19,
    this.width = 170,
    this.onDark = false,
  });

  final double fontSize;
  final double width;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Saudi Factories B2B',
      image: true,
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: CustomPaint(
            size: Size(
              SFWordmarkPaths.width * fontSize / 19,
              fontSize * 1.55 + 3.5,
            ),
            painter: _WordmarkPainter(fontSize: fontSize, onDark: onDark),
          ),
        ),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter({required this.fontSize, required this.onDark});

  final double fontSize;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = fontSize / 19;
    final lineHeight = fontSize * 1.55;
    canvas.save();
    canvas.translate(0, (lineHeight - SFWordmarkPaths.height * scale) / 2);
    canvas.scale(scale);
    final paint = Paint();
    canvas.drawPath(SFWordmarkPaths.saudi, paint..color = SFColors.green);
    canvas.drawPath(
      SFWordmarkPaths.factories,
      paint..color = onDark ? SFColors.white : SFColors.darkGreen,
    );
    canvas.drawPath(SFWordmarkPaths.b2b, paint..color = SFColors.gold);
    canvas.restore();

    // The brand's underline keeps its physical green-to-gold direction in RTL.
    final rule = Rect.fromLTWH(0, lineHeight + 2, size.width, 1.5);
    paint.shader = const LinearGradient(
      colors: [SFColors.midGreen, SFColors.green, SFColors.gold],
    ).createShader(rule);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rule, const Radius.circular(2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) =>
      oldDelegate.fontSize != fontSize || oldDelegate.onDark != onDark;
}
