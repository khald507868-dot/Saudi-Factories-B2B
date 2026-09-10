import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/pages/home_page.dart';
import 'package:saudi_factories/services/delivery_address_service.dart';
import 'package:saudi_factories/services/promotion_service.dart';
import 'package:saudi_factories/widgets/home_product_details.dart';
import 'package:saudi_factories/widgets/price_text.dart';

const _products = [
  {
    'id': 101,
    'factory_id': 8,
    'name': 'بطارية صناعية',
    'price': 44.0,
    'image': '',
    'images': <String>[],
    'tiers': <Map<String, Object>>[],
  },
  {
    'id': 202,
    'factory_id': 9,
    'name': 'أنبوب فولاذي',
    'price': 17.5,
    'image': '',
    'images': <String>[],
    'tiers': <Map<String, Object>>[],
  },
];

Widget _host() => I18nScope(
  i18n: I18n('ar'),
  child: MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const HomePage(),
  ),
);

Finder _details(int id) => find.byWidgetPredicate(
  (widget) => widget is HomeProductDetails && widget.product.id == id,
);

Future<void> _settleData(WidgetTester tester) async {
  // المنتجات ثم RPC التقييمات ينشئان مرحلتين من FutureBuilder.
  for (var phase = 0; phase < 3; phase++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  await tester.pumpAndSettle();
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _expectProductAndPrice(
  WidgetTester tester,
  int id,
  String name,
  String price,
) {
  final details = _details(id);
  expect(details, findsOneWidget);
  expect(find.text(name), findsOneWidget);
  final priceWidget = tester.widget<SFPriceText>(
    find.descendant(of: details, matching: find.byType(SFPriceText)),
  );
  expect(priceWidget.text, contains(price));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ratingRequests = <Map<String, dynamic>>[];
  var promotionsReads = 0;
  var failRatings = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://home-product-strip-test.invalid',
      publishableKey: 'test-public-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        Object data = <Map<String, Object>>[];
        var status = 200;
        switch (request.url.path) {
          case '/rest/v1/products':
            data = _products;
          case '/rest/v1/rpc/get_product_ratings':
            ratingRequests.add(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            if (failRatings) {
              status = 403;
              data = {
                'code': '42501',
                'message': 'ratings temporarily unavailable',
              };
            } else {
              data = [
                {'product_id': 202, 'rating_avg': 4.6, 'rating_count': 7},
              ];
            }
          case '/rest/v1/home_promotions':
            promotionsReads++;
        }
        return http.Response(
          jsonEncode(data),
          status,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await DeliveryAddressService.instance.start();
  });
  tearDownAll(() async {
    DeliveryAddressService.instance.dispose();
    await Supabase.instance.dispose();
  });
  setUp(() {
    ratingRequests.clear();
    promotionsReads = 0;
    failRatings = false;
  });

  testWidgets(
    'الرئيسية تجمع تقييمات المنتجات بطلب واحد وتربطها بالمنتج الصحيح',
    (tester) async {
      _viewport(tester);
      await tester.pumpWidget(_host());
      await _settleData(tester);
      expect(ratingRequests, hasLength(1));
      expect(
        ratingRequests.single['p_product_ids'],
        unorderedEquals([101, 202]),
      );
      _expectProductAndPrice(tester, 101, 'بطارية صناعية', '44.00');
      _expectProductAndPrice(tester, 202, 'أنبوب فولاذي', '17.50');
      final unrated = tester.widget<HomeProductDetails>(_details(101));
      final rated = tester.widget<HomeProductDetails>(_details(202));
      expect(rated.rating?.average, 4.6);
      expect(rated.rating?.count, 7);
      expect(rated.ratingLoading, isFalse);
      expect(rated.ratingFailed, isFalse);
      expect(unrated.rating?.count, 0);
      expect(unrated.ratingLoading, isFalse);
      expect(unrated.ratingFailed, isFalse);
      expect(
        find.descendant(of: _details(202), matching: find.text('4.6 (7)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _details(101), matching: find.text('— (0)')),
        findsOneWidget,
      );

      // تحديث الإعلانات يعيد بناء الرئيسية دون إعادة طلب تقييمات نفس المنتجات.
      PromotionService.changes.value++;
      await _settleData(tester);
      expect(promotionsReads, 2);
      expect(ratingRequests, hasLength(1));
      expect(tester.widget<HomeProductDetails>(_details(202)).rating?.count, 7);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'فشل خدمة التقييم يبقي المنتجات والأسعار ولا يقدّمها كمنتجات بلا مراجعات',
    (tester) async {
      _viewport(tester);
      failRatings = true;
      await tester.pumpWidget(_host());
      await _settleData(tester);
      expect(ratingRequests, hasLength(1));
      _expectProductAndPrice(tester, 101, 'بطارية صناعية', '44.00');
      _expectProductAndPrice(tester, 202, 'أنبوب فولاذي', '17.50');
      for (final id in [101, 202]) {
        final details = tester.widget<HomeProductDetails>(_details(id));
        expect(details.ratingFailed, isTrue);
        expect(details.ratingLoading, isFalse);
        expect(details.rating, isNull);
        expect(
          find.descendant(of: _details(id), matching: find.text('0.0')),
          findsNothing,
        );
        expect(
          find.descendant(of: _details(id), matching: find.text('— (0)')),
          findsNothing,
        );
        expect(
          find.descendant(of: _details(id), matching: find.text('—')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
