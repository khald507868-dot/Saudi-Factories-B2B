import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/main.dart' show PhoneColumn;
import 'package:saudi_factories/services/delivery_address_service.dart';
import 'package:saudi_factories/widgets/home_header.dart';

const _capture = ValueKey('header-edges-capture');
const _contentColor = Color(0xFF092714);

Widget _host(ScrollController scroll) => I18nScope(
  i18n: I18n('ar'),
  child: MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: RepaintBoundary(
      key: _capture,
      child: PhoneColumn(
        child: Builder(
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              extendBodyBehindAppBar: true,
              appBar: HomeHeader(
                scrollController: scroll,
                promotionColor: _contentColor,
                searchHint: context.t('search_placeholder'),
                onSearchSubmitted: (_) {},
                onStatsPressed: () {},
              ),
              body: ListView(
                controller: scroll,
                padding: const EdgeInsets.only(top: HomeHeader.height),
                children: const [
                  SizedBox(
                    height: 2000,
                    child: ColoredBox(color: _contentColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<List<Color>> _samples(WidgetTester tester, List<Offset> points) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return points.map((point) {
        final index = (point.dy.round() * image.width + point.dx.round()) * 4;
        return Color.fromARGB(
          bytes!.getUint8(index + 3),
          bytes.getUint8(index),
          bytes.getUint8(index + 1),
          bytes.getUint8(index + 2),
        );
      }).toList();
    } finally {
      image.dispose();
    }
  }))!;
}

String _rgb(Color color) =>
    '${(color.r * 255).round()},${(color.g * 255).round()},${(color.b * 255).round()}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(() => DeliveryAddressService.instance.dispose());

  testWidgets('زجاج الترويسة يصل إلى طرفي عمود الجوال دون تسرّب الهامش الأبيض', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await DeliveryAddressService.instance.start();
    for (final width in [1200.0, 320.0]) {
      tester.view.physicalSize = Size(width, 700);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(_host(scroll));
      scroll.jumpTo(100);
      await tester.pumpAndSettle();

      final header = tester.getRect(find.byType(HomeHeader));
      final background = tester.getRect(
        find.byKey(const ValueKey('home-header-background')),
      );
      final columnWidth = width > 430 ? 430.0 : width;
      expect(
        header,
        Rect.fromLTWH((width - columnWidth) / 2, 0, columnWidth, 84),
      );
      expect(background, header);
      final colors = await _samples(tester, [
        Offset(header.left + 2, 40),
        Offset(header.left + 8, 40),
        Offset(header.left + 80, 40),
        Offset(header.right - 8, 40),
        Offset(header.right - 3, 40),
      ]);
      // تُسجل القيم لتفسير إخفاق الحواف من ناتج الاختبار دون صور خارجية.
      debugPrint(
        'header width=$width RGB left+2,left+8,interior,right-8,right-3: ${colors.map(_rgb).join(' | ')}',
      );
      final interior = colors[2];
      for (final edge in [colors[0], colors[1], colors[3], colors[4]]) {
        expect(
          (edge.r - interior.r).abs(),
          lessThanOrEqualTo(3 / 255),
          reason: 'القناة الحمراء عند الحافة',
        );
        expect(
          (edge.g - interior.g).abs(),
          lessThanOrEqualTo(3 / 255),
          reason: 'القناة الخضراء عند الحافة',
        );
        expect(
          (edge.b - interior.b).abs(),
          lessThanOrEqualTo(3 / 255),
          reason: 'القناة الزرقاء عند الحافة',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
