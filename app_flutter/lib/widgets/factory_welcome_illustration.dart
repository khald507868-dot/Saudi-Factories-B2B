import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// رسم متجهي أصلي يربط التصنيع بالمنتجات الجاهزة والشحن.
/// الشاشة تتحكم في الحركة، ويمكنها تثبيت الرسم عند تفعيل تقليل الحركة.
class FactoryWelcomeIllustration extends StatelessWidget {
  const FactoryWelcomeIllustration({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AspectRatio(
      aspectRatio: 360 / 310,
      child: RepaintBoundary(
        child: CustomPaint(painter: _FactoryWelcomePainter(animation)),
      ),
    ),
  );
}

class _FactoryWelcomePainter extends CustomPainter {
  _FactoryWelcomePainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _mint = Color(0xFFD8EBDF);
  static const _paleMint = Color(0xFFE8F2EA);
  static const _wall = Color(0xFFB8D8C5);
  static const _side = Color(0xFF83B398);
  static const _cream = Color(0xFFF9EAC0);
  static const _parcel = Color(0xFFE4C776);

  Paint _fill(Color color) => Paint()..color = color;

  Paint _line(Color color, [double width = 2]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _roundRect(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    double radius,
    Color color,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        Radius.circular(radius),
      ),
      _fill(color),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final progress = animation.value.clamp(0.0, 1.0);
    final phase = progress * math.pi * 2;
    canvas.save();
    canvas.scale(size.width / 360, size.height / 310);

    // خلفية ناعمة تترك فراغًا مريحًا حول عناصر الرسم.
    final landscape = Path()
      ..moveTo(40, 216)
      ..cubicTo(15, 163, 41, 99, 92, 81)
      ..cubicTo(131, 66, 146, 89, 181, 73)
      ..cubicTo(231, 49, 288, 83, 305, 130)
      ..cubicTo(324, 181, 331, 216, 303, 245)
      ..cubicTo(260, 282, 184, 268, 140, 272)
      ..cubicTo(87, 277, 56, 254, 40, 216)
      ..close();
    canvas.drawPath(landscape, _fill(_paleMint));
    _paintSky(canvas, phase);
    _paintDistantBuildings(canvas);

    canvas.drawOval(
      const Rect.fromLTWH(36, 256, 292, 22),
      _fill(SFColors.midGreen.withValues(alpha: .08)),
    );
    canvas.drawLine(
      const Offset(32, 269),
      const Offset(329, 269),
      _line(SFColors.border, 1.5),
    );

    _paintFactory(canvas);
    _paintConveyor(canvas, progress);
    _paintTruck(canvas, phase);
    _paintPlant(canvas);
    _paintGear(canvas, phase);

    canvas.restore();
  }

  void _paintSky(Canvas canvas, double phase) {
    final sunPosition = Offset(281, 66 + math.sin(phase) * 1.5);
    canvas.drawCircle(
      sunPosition,
      33,
      _fill(SFColors.gold.withValues(alpha: .08)),
    );
    canvas.drawCircle(sunPosition, 22, _fill(_cream));
    canvas.drawCircle(sunPosition, 15, _fill(SFColors.gold));
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 + phase * .035;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        sunPosition + direction * 26,
        sunPosition + direction * 29,
        _line(SFColors.gold.withValues(alpha: .55), 2),
      );
    }

    canvas.save();
    canvas.translate(math.sin(phase) * 4, 0);
    final cloud = Path()
      ..moveTo(91, 59)
      ..cubicTo(89, 50, 98, 44, 106, 48)
      ..cubicTo(110, 34, 132, 35, 136, 49)
      ..cubicTo(146, 45, 155, 52, 153, 61)
      ..lineTo(93, 61)
      ..close();
    canvas.drawPath(cloud, _fill(Colors.white.withValues(alpha: .9)));
    canvas.restore();

    // مسار منقّط يربط إنتاج المصنع بالتوزيع.
    final route = Path()
      ..moveTo(191, 88)
      ..cubicTo(223, 74, 249, 106, 266, 131);
    final routeMetric = route.computeMetrics().first;
    for (double distance = 0; distance < routeMetric.length; distance += 8) {
      final point = routeMetric.getTangentForOffset(distance)!.position;
      canvas.drawCircle(
        point,
        1.4,
        _fill(SFColors.softGreen.withValues(alpha: .5)),
      );
    }
    final marker = routeMetric
        .getTangentForOffset(
          ((phase / (2 * math.pi) + .28) % 1) * routeMetric.length,
        )!
        .position;
    canvas.drawCircle(marker, 3.3, _fill(SFColors.gold));

    canvas.drawCircle(
      Offset(321, 174 + math.sin(phase) * 3),
      3,
      _fill(SFColors.green.withValues(alpha: .5)),
    );
    canvas.drawCircle(
      Offset(37, 143 - math.sin(phase) * 2),
      2.5,
      _fill(SFColors.gold.withValues(alpha: .65)),
    );
    canvas.drawLine(
      const Offset(221, 45),
      const Offset(221, 53),
      _line(SFColors.green.withValues(alpha: .55), 1.7),
    );
    canvas.drawLine(
      const Offset(217, 49),
      const Offset(225, 49),
      _line(SFColors.green.withValues(alpha: .55), 1.7),
    );
  }

  void _paintDistantBuildings(Canvas canvas) {
    _roundRect(canvas, 245, 147, 51, 70, 3, _mint);
    _roundRect(canvas, 257, 130, 20, 87, 3, _mint);
    _roundRect(canvas, 260, 126, 14, 6, 2, SFColors.border);
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        _roundRect(
          canvas,
          254 + column * 12,
          157 + row * 17,
          6,
          9,
          1.5,
          const Color(0xFFC2DECC),
        );
      }
    }
    canvas.drawPath(
      Path()
        ..moveTo(222, 212)
        ..lineTo(222, 169)
        ..lineTo(239, 160)
        ..lineTo(239, 212)
        ..close(),
      _fill(SFColors.border),
    );
  }

  void _paintFactory(Canvas canvas) {
    // حافة مضيئة وجانب مظلل يمنحان الرسم عمقًا دون صور خارجية.
    _roundRect(canvas, 60, 94, 18, 61, 2, SFColors.midGreen);
    _roundRect(canvas, 72, 95, 6, 60, 1, SFColors.darkGreen);
    _roundRect(canvas, 56, 89, 26, 9, 2.5, SFColors.green);
    _roundRect(canvas, 61, 92, 15, 2, 1, _wall);

    final side = Path()
      ..moveTo(209, 145)
      ..lineTo(232, 160)
      ..lineTo(232, 231)
      ..lineTo(209, 231)
      ..close();
    canvas.drawPath(side, _fill(_side));
    final front = Path()
      ..moveTo(48, 146)
      ..lineTo(90, 117)
      ..lineTo(90, 144)
      ..lineTo(134, 117)
      ..lineTo(134, 144)
      ..lineTo(178, 117)
      ..lineTo(178, 144)
      ..lineTo(209, 144)
      ..lineTo(209, 231)
      ..lineTo(48, 231)
      ..close();
    canvas.drawPath(front, _fill(_wall));

    final roof = Path()
      ..moveTo(46, 146)
      ..lineTo(90, 115)
      ..lineTo(90, 143)
      ..lineTo(134, 115)
      ..lineTo(134, 143)
      ..lineTo(178, 115)
      ..lineTo(178, 143)
      ..lineTo(211, 143)
      ..lineTo(234, 158);
    canvas.drawPath(roof, _line(SFColors.darkGreen, 5));
    canvas.drawLine(
      const Offset(51, 151),
      const Offset(206, 151),
      _line(const Color(0xFFDCEDE2), 2),
    );

    // نوافذ الورشة المضيئة والفتحات العلوية الصغيرة.
    for (var i = 0; i < 3; i++) {
      final x = 63.0 + i * 28;
      _roundRect(canvas, x, 164, 20, 26, 2.5, SFColors.midGreen);
      _roundRect(canvas, x + 3, 167, 14, 19, 1, _cream);
      canvas.drawLine(
        Offset(x + 10, 167),
        Offset(x + 10, 186),
        _line(SFColors.midGreen, 2),
      );
      canvas.drawLine(
        Offset(x + 3, 177),
        Offset(x + 17, 177),
        _line(SFColors.midGreen, 2),
      );
      canvas.drawPath(
        Path()
          ..moveTo(75 + i * 44, 135)
          ..lineTo(82 + i * 44, 130)
          ..lineTo(82 + i * 44, 140)
          ..lineTo(75 + i * 44, 140)
          ..close(),
        _fill(SFColors.green),
      );
    }

    _roundRect(canvas, 157, 167, 36, 64, 3, SFColors.darkGreen);
    _roundRect(canvas, 161, 171, 28, 21, 1, SFColors.midGreen);
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(162, 176.0 + i * 6),
        Offset(188, 176.0 + i * 6),
        _line(SFColors.softGreen, 1),
      );
    }
    _roundRect(canvas, 154, 166, 42, 5, 2, SFColors.green);
    _roundRect(canvas, 48, 225, 109, 6, 1, SFColors.green);

    canvas.drawLine(
      const Offset(216, 172),
      const Offset(225, 178),
      _line(SFColors.midGreen, 3),
    );
    canvas.drawLine(
      const Offset(216, 182),
      const Offset(225, 188),
      _line(SFColors.midGreen, 3),
    );
  }

  void _paintConveyor(Canvas canvas, double progress) {
    canvas.drawLine(
      const Offset(91, 247),
      const Offset(88, 266),
      _line(SFColors.midGreen, 5),
    );
    canvas.drawLine(
      const Offset(208, 247),
      const Offset(211, 266),
      _line(SFColors.midGreen, 5),
    );
    _roundRect(canvas, 78, 238, 149, 14, 7, SFColors.darkGreen);
    _roundRect(canvas, 81, 241, 143, 8, 4, SFColors.midGreen);
    for (var i = 0; i < 12; i++) {
      final x = 86.0 + i * 12;
      canvas.drawCircle(Offset(x, 245), 2.1, _fill(_side));
    }

    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(78, 198, 149, 40));
    for (var i = -1; i < 4; i++) {
      final x = 88 + i * 45 + progress * 45;
      _paintParcel(canvas, x, 215, 26, 23);
    }
    canvas.restore();
  }

  void _paintParcel(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
  ) {
    _roundRect(canvas, x, y, width, height, 2.5, _parcel);
    canvas.drawPath(
      Path()
        ..moveTo(x + width - 6, y)
        ..lineTo(x + width, y + 3)
        ..lineTo(x + width, y + height)
        ..lineTo(x + width - 6, y + height - 1)
        ..close(),
      _fill(SFColors.gold),
    );
    _roundRect(canvas, x + width * .38, y, 5, 9, .5, _cream);
    _roundRect(canvas, x + 4, y + height - 7, 7, 2, .5, _cream);
  }

  void _paintTruck(Canvas canvas, double phase) {
    canvas.save();
    canvas.translate(math.sin(phase) * 3, math.sin(phase * 2) * .5);
    canvas.drawOval(
      const Rect.fromLTWH(231, 258, 88, 10),
      _fill(SFColors.darkGreen.withValues(alpha: .09)),
    );
    _roundRect(canvas, 230, 207, 56, 42, 5, Colors.white);
    _roundRect(canvas, 231, 207, 55, 7, 4, SFColors.green);
    _roundRect(canvas, 230, 237, 56, 12, 2, SFColors.green);

    final cab = Path()
      ..moveTo(286, 220)
      ..lineTo(300, 220)
      ..quadraticBezierTo(303, 220, 305, 224)
      ..lineTo(315, 239)
      ..lineTo(315, 249)
      ..lineTo(284, 249)
      ..lineTo(284, 223)
      ..quadraticBezierTo(284, 220, 286, 220)
      ..close();
    canvas.drawPath(cab, _fill(SFColors.midGreen));
    final windshield = Path()
      ..moveTo(290, 225)
      ..lineTo(299, 225)
      ..lineTo(307, 237)
      ..lineTo(290, 237)
      ..close();
    canvas.drawPath(windshield, _fill(_mint));
    canvas.drawLine(
      const Offset(292, 228),
      const Offset(299, 228),
      _line(Colors.white, 1.5),
    );
    _roundRect(canvas, 288, 241, 6, 2, 1, _side);
    _roundRect(canvas, 311, 240, 5, 4, 1, _cream);
    _roundRect(canvas, 226, 248, 93, 5, 2, SFColors.darkGreen);
    _paintParcel(canvas, 248, 217, 21, 20);

    for (final x in [244.0, 300.0]) {
      canvas.drawCircle(Offset(x, 255), 9, _fill(SFColors.darkGreen));
      canvas.drawCircle(Offset(x, 255), 4.7, _fill(_wall));
      canvas.drawCircle(Offset(x, 255), 2, _fill(SFColors.midGreen));
      final wheelDirection = Offset(math.cos(phase * 2), math.sin(phase * 2));
      canvas.drawLine(
        Offset(x, 255) + wheelDirection * 2,
        Offset(x, 255) + wheelDirection * 4,
        _line(Colors.white, 1.4),
      );
    }
    canvas.restore();
  }

  void _paintPlant(Canvas canvas) {
    canvas.drawLine(
      const Offset(51, 267),
      const Offset(51, 240),
      _line(SFColors.midGreen, 2.5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(51, 251)
        ..cubicTo(35, 250, 33, 239, 36, 233)
        ..cubicTo(47, 234, 53, 241, 51, 251)
        ..close(),
      _fill(SFColors.green),
    );
    canvas.drawPath(
      Path()
        ..moveTo(51, 259)
        ..cubicTo(65, 257, 70, 247, 68, 242)
        ..cubicTo(56, 242, 50, 249, 51, 259)
        ..close(),
      _fill(SFColors.midGreen),
    );
  }

  void _paintGear(Canvas canvas, double phase) {
    canvas.save();
    canvas.translate(47, 79);
    canvas.rotate(phase * .22);
    final gear = Path();
    for (var i = 0; i < 48; i++) {
      final angle = i * math.pi / 24;
      final radius = i % 4 == 0 || i % 4 == 3 ? 13.0 : 16.5;
      final point = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        gear.moveTo(point.dx, point.dy);
      } else {
        gear.lineTo(point.dx, point.dy);
      }
    }
    gear.close();
    canvas.drawPath(gear, _fill(SFColors.gold));
    canvas.drawCircle(Offset.zero, 8, _fill(SFColors.pageBg));
    canvas.drawCircle(Offset.zero, 3, _fill(_cream));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FactoryWelcomePainter oldDelegate) =>
      oldDelegate.animation != animation;
}
