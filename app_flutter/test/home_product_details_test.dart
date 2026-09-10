import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:saudi_factories/core/currency.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/services/factory_service.dart';
import 'package:saudi_factories/services/reviews_service.dart';
import 'package:saudi_factories/widgets/home_product_details.dart';
import 'package:saudi_factories/widgets/price_text.dart';

Future<void> _pumpDetails(
  WidgetTester tester,
  HomeProductDetails details, {
  String language = 'ar',
  double textScale = 1,
}) => tester.pumpWidget(
  I18nScope(
    i18n: I18n(language),
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: language == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(body: Center(child: details)),
    ),
  ),
);

SFProduct _product({double price = 100}) =>
    SFProduct({'id': 1, 'name': 'منتج تجريبي', 'price': price});

String _price(WidgetTester tester) =>
    tester.widget<SFPriceText>(find.byType(SFPriceText)).text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SFCurrency.instance.load();
  });

  testWidgets('السعر يتبع مدى الشرائح ويظهر التقييم الحقيقي بمنزلة واحدة', (
    tester,
  ) async {
    await _pumpDetails(
      tester,
      HomeProductDetails(
        product: SFProduct({
          'id': 1,
          'price': 100,
          'tiers': [
            {'min': 1, 'max': 9, 'price': 20},
            {'min': 10, 'price': 12.5},
          ],
        }),
        rating: const SFProductRating(average: 4.26, count: 12),
      ),
    );

    expect(_price(tester), '12.50 – 20.00 ﷼');
    expect(find.text('4.3 (12)'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.byTooltip('12.50 – 20.00 ﷼'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('يتحدث السعر عند تغيير العملة دون إعادة بناء الأب', (
    tester,
  ) async {
    await _pumpDetails(tester, HomeProductDetails(product: _product()));
    expect(_price(tester), '100.00 ﷼');

    await SFCurrency.instance.setCurrency('USD');
    await tester.pump();
    expect(_price(tester), '26.67 \$');

    await SFCurrency.instance.setCurrency('KWD');
    await tester.pump();
    expect(_price(tester), '8.170 د.ك');
    expect(tester.takeException(), isNull);
  });

  testWidgets('غياب السعر يعرض عند الطلب بالترجمة واتجاهها', (tester) async {
    await _pumpDetails(tester, HomeProductDetails(product: _product(price: 0)));
    final arabic = I18n('ar');
    expect(_price(tester), arabic.t('product_price_on_request'));
    expect(
      tester.widget<SFPriceText>(find.byType(SFPriceText)).textDirection,
      TextDirection.rtl,
    );

    await _pumpDetails(
      tester,
      HomeProductDetails(product: _product(price: -1)),
      language: 'en',
    );
    expect(_price(tester), I18n('en').t('product_price_on_request'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('يفرق بين عدم وجود مراجعات والتقييم المجهول والفشل والتحميل', (
    tester,
  ) async {
    final i18n = I18n('ar');
    final product = _product();
    const empty = SFProductRating(average: 0, count: 0);
    await _pumpDetails(
      tester,
      HomeProductDetails(product: product, rating: empty),
    );
    expect(find.text('— (0)'), findsOneWidget);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    expect(find.byTooltip(i18n.t('reviews_none')), findsOneWidget);
    expect(find.text('0.0 (0)'), findsNothing);

    await _pumpDetails(tester, HomeProductDetails(product: product));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('— (0)'), findsNothing);

    await _pumpDetails(
      tester,
      HomeProductDetails(product: product, rating: empty, ratingFailed: true),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('— (0)'), findsNothing);
    expect(find.byTooltip(i18n.t('fx_failed')), findsOneWidget);
    expect(_price(tester), '100.00 ﷼');

    await _pumpDetails(
      tester,
      HomeProductDetails(
        product: product,
        rating: const SFProductRating(average: 5, count: 8),
        ratingLoading: true,
      ),
    );
    expect(find.text('…'), findsOneWidget);
    expect(find.text('5.0 (8)'), findsNothing);
    expect(find.byTooltip(i18n.t('fx_loading')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ar', 'en']) {
    testWidgets('لا يتجاوز عرض88 عند تكبير النص باللغة $language', (
      tester,
    ) async {
      await _pumpDetails(
        tester,
        HomeProductDetails(
          product: _product(price: 987654321.25),
          rating: const SFProductRating(average: 4.95, count: 1234567),
        ),
        language: language,
        textScale: 3,
      );
      final finder = find.byType(HomeProductDetails);
      final size = tester.getSize(finder);
      final context = tester.element(finder);
      expect(size.width, 88);
      expect(size.height, closeTo(HomeProductDetails.heightFor(context), .001));
      expect(size.height, greaterThan(100));
      expect(
        find.byTooltip('${I18n(language).t('reviews_title')}: 5.0 (1234567)'),
        findsOneWidget,
      );
      expect(tester.widget<SFPriceText>(find.byType(SFPriceText)).maxLines, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
