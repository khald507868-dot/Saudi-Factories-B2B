import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saudi_factories/core/currency.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/core/pricing.dart';
import 'package:saudi_factories/services/commerce_service.dart';
import 'package:saudi_factories/services/factory_service.dart';
import 'package:saudi_factories/services/messages_service.dart';
import 'package:saudi_factories/services/orders_service.dart';
import 'package:saudi_factories/widgets/catalog_product_card.dart';
import 'package:saudi_factories/pages/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SFCurrency.instance.load();
  });

  test('شرائح الكمية تتغير عند الحد وتعود للسعر الأساسي خارجها', () {
    final tiers = SFPriceTier.parseList([
      {'min': 1, 'max': 9, 'price': 12},
      {'min': 10, 'max': 19, 'price': '10.50'},
      {'min': 20, 'max': null, 'price': 8},
      {'min': -1, 'price': 1},
      {'min': 2, 'max': 1, 'price': 1},
    ]);
    expect(tiers, hasLength(3));
    expect(SFPriceCalculation.unitPrice(15, tiers, 9), 12);
    expect(SFPriceCalculation.unitPrice(15, tiers, 10), 10.5);
    expect(SFPriceCalculation.unitPrice(15, tiers, 20), 8);
    expect(SFPriceCalculation.unitPrice(15, tiers.take(2).toList(), 20), 15);
  });

  test('تقدير الطلب يطابق رسوم التوصيل والدفع وضريبة الخادم', () {
    final estimate = SFOrderEstimate(100);
    expect(estimate.shipping, 30);
    expect(estimate.paymentFee, 1.3);
    expect(estimate.vat, 19.7);
    expect(estimate.total, 151);
  });

  test('إجمالي العرض يساوي سعر الوحدة الظاهر في العملات المختلفة', () async {
    final currency = SFCurrency.instance;
    expect(SFCurrency.currencies, hasLength(30));
    await currency.setCurrency('USD');
    expect(currency.roundConverted(10), 2.67);
    expect(
      currency.format(currency.lineAmount(10, 3), withSymbol: false),
      '8.01',
    );
    await currency.setCurrency('KWD');
    expect(currency.decimals, 3);
    await currency.setCurrency('JPY');
    expect(currency.decimals, 0);
    await currency.setCurrency('INVALID');
    expect(currency.code, 'JPY');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sf_currency'), 'JPY');
    expect(SFCurrency.formatSar(100), contains('100.00'));
  });

  test('السلة تعيد تسعير الشريحة عند تغيير الكمية', () {
    final item = CartItem.fromRow({
      'id': 1,
      'product_id': 5,
      'quantity': 9,
      'products': {
        'id': 5,
        'factory_id': 2,
        'name': 'منتج',
        'price': 12,
        'tiers': [
          {'min': 10, 'price': 8},
        ],
        'images': ['https://example.com/product.jpg'],
        'factories': {'name': 'مصنع'},
      },
    });
    expect(item.unitPrice, 12);
    expect(item.copyWith(quantity: 10).lineTotal, 80);
    expect(item.image, 'https://example.com/product.jpg');
  });

  test('الفاتورة تستعمل القيم المثبتة والدفع يقتصر على المالك والمدير', () {
    final order = SFOrder.fromRow({
      'id': 'a-b',
      'factory_id': 3,
      'status': 'awaiting_payment',
      'currency': 'SAR',
      'total': '151.00',
      'vat_amount': '19.70',
      'order_items': [
        {
          'product_name': 'منتج',
          'unit_price': 10,
          'quantity': 9,
          'line_total': 100,
        },
      ],
    });
    expect(order.items.single.lineTotal, 100);
    expect(order.canConfirmPayment({3}), isTrue);
    expect(order.canConfirmPayment({4}), isFalse);
    expect(order.canConfirmPayment({}, isAdmin: true), isTrue);
    expect(jsonDecode(order.referencePayload)['currency'], 'SAR');
    final paid = SFOrder.fromRow({
      'id': 'a',
      'factory_id': 3,
      'status': 'paid',
    });
    expect(paid.canConfirmPayment({3}), isFalse);
  });

  test('بطاقة المنتج تبقى مرتبطة برسالة المحادثة بعد التطبيع', () {
    final product = SFProductAttachment.fromRow({
      'product_id': 2,
      'name': 'منتج',
      'image': '',
      'price': 12,
    });
    final message = SFMessage.fromRow(
      {
        'id': 1,
        'sender_id': 'me',
        'body': 'استفسار',
        'attachment_type': 'product',
        'product_id': 2,
      },
      'me',
      product: product,
    );
    expect(message.mine, isTrue);
    expect(message.productId, 2);
    expect(message.copyWith(pending: true).product?.name, 'منتج');
  });

  test('روابط المصنع والوسائط تقبل http/https فقط', () {
    expect(normalizedWebsite('example.com')?.scheme, 'https');
    expect(normalizedWebsite('javascript:alert(1)'), isNull);
    expect(normalizedWebsite('data:text/html,hello'), isNull);
    expect(safeMediaUrl('https://example.com/image.png'), isNotEmpty);
    expect(safeMediaUrl('http-no-url'), isEmpty);
  });

  testWidgets('بطاقات المنتجات لا تتجاوز شبكة هاتف ضيق بالعربية', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final product = SFProduct({
      'id': 1,
      'name': 'اسم منتج عربي طويل لاختبار العرض على الجوال',
      'price': 12,
      'tiers': [
        {'min': 1, 'price': 12},
        {'min': 10, 'price': 9},
      ],
      'factories': {'name': 'مصنع تجريبي للعرض', 'status': 'approved'},
    });
    await tester.pumpWidget(
      I18nScope(
        i18n: I18n('ar'),
        child: MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: .74,
                padding: const EdgeInsets.all(16),
                crossAxisSpacing: 12,
                children: [
                  CatalogProductCard(product: product),
                  CatalogProductCard(product: product),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.verified), findsNWidgets(2));
  });

  testWidgets('اختيار العملة من الإعدادات يحفظ الاختيار', (tester) async {
    await tester.pumpWidget(
      I18nScope(
        i18n: I18n('en'),
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.tap(find.text('Choose currency'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'USD');
    await tester.pumpAndSettle();
    await tester.tap(find.text('US Dollar'));
    await tester.pumpAndSettle();
    expect(SFCurrency.instance.code, 'USD');
    expect(tester.takeException(), isNull);
  });
}
