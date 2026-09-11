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
import 'package:saudi_factories/widgets/slow_auto_scroll.dart';

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

Future<void> _settleData(
  WidgetTester tester, {
  bool settleAnimations = true,
}) async {
  // المنتجات ثم RPC التقييمات ينشئان مرحلتين من FutureBuilder.
  for (var phase = 0; phase < 3; phase++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  if (settleAnimations) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
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
  var productRows = _products;
  var ratingRows = <Map<String, Object>>[
    {'product_id': 202, 'rating_avg': 4.6, 'rating_count': 7},
  ];

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
            data = productRows;
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
              data = ratingRows;
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
    productRows = _products;
    ratingRows = [
      {'product_id': 202, 'rating_avg': 4.6, 'rating_count': 7},
    ];
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

  testWidgets(
    'الدوران يصل آخر المنتجات بأولها مع بقاء السعر والتقييم وطلب واحد',
    (tester) async {
      _viewport(tester);
      productRows = [
        for (var i = 0; i < 7; i++)
          {
            ..._products.first,
            'id': 101 * (i + 1),
            'name': 'منتج صناعي ${i + 1}',
            'price': 11.25 + i * 7.5,
          },
      ];
      ratingRows = [
        for (var i = 0; i < productRows.length; i++)
          {
            'product_id': productRows[i]['id']!,
            'rating_avg': 2.0 + i * .4,
            'rating_count': 3 + i,
          },
      ];
      final expectedProducts = {
        for (final row in productRows) row['id'] as int: row,
      };
      final expectedRatings = {
        for (final row in ratingRows) row['product_id'] as int: row,
      };
      await tester.pumpWidget(_host());
      await _settleData(tester, settleAnimations: false);

      final autoScroll = find.byType(SlowAutoScroll);
      final productsList = find.descendant(
        of: autoScroll,
        matching: find.byType(ListView),
      );
      final controller = tester.widget<ListView>(productsList).controller!;
      final cycle = tester.widget<SlowAutoScroll>(autoScroll).cycleExtent;
      expect(cycle, greaterThan(tester.getSize(productsList).width));
      expect(controller.offset, closeTo(cycle, 1));

      Map<int, Rect> checkVisibleProducts() {
        final viewport = tester.getRect(productsList);
        final visible = <int, Rect>{};
        for (final element in find.byType(HomeProductDetails).evaluate()) {
          final details = element.widget as HomeProductDetails;
          final finder = find.byWidget(details);
          final rect = tester.getRect(finder);
          if (!viewport.contains(rect.center)) continue;
          final expected = expectedProducts[details.product.id]!;
          final rating = expectedRatings[details.product.id]!;
          expect(details.product.name, expected['name']);
          expect(details.product.minPrice, expected['price']);
          expect(details.ratingLoading, isFalse);
          expect(details.ratingFailed, isFalse);
          expect(details.rating?.average, rating['rating_avg']);
          expect(details.rating?.count, rating['rating_count']);
          final price = tester.widget<SFPriceText>(
            find.descendant(of: finder, matching: find.byType(SFPriceText)),
          );
          expect(
            price.text,
            contains((expected['price'] as num).toStringAsFixed(2)),
          );
          expect(
            find.descendant(
              of: finder,
              matching: find.text(
                '${(rating['rating_avg'] as num).toStringAsFixed(1)} (${rating['rating_count']})',
              ),
            ),
            findsOneWidget,
          );
          visible[details.product.id] = rect;
        }
        expect(visible.length, greaterThanOrEqualTo(3));
        return visible;
      }

      checkVisibleProducts();
      // نقترب بالسحب البرمجي من الوصلة، ثم تعبرها حركة الشريط الطبيعية.
      controller.jumpTo(2 * cycle - 80);
      await tester.pump();
      var previousVisible = checkVisibleProducts();
      expect(previousVisible.keys, containsAll([707, 101]));
      var crossedCycle = false;
      for (var frame = 0; frame < 400; frame++) {
        final previousOffset = controller.offset;
        await tester.pump(const Duration(milliseconds: 20));
        final visible = checkVisibleProducts();
        if (controller.offset < previousOffset - cycle / 2) {
          crossedCycle = true;
          // تبديل النسخ لا يغيّر موضع المنتج المرئي أو يعكس اتجاه حركته.
          expect(
            visible[101]!.center.dx - previousVisible[101]!.center.dx,
            closeTo(.24, .01),
          );
        }
        previousVisible = visible;
      }
      expect(crossedCycle, isTrue);
      expect(controller.offset, inExclusiveRange(cycle, cycle + 32));
      expect(previousVisible.keys, contains(101));
      expect(previousVisible.keys, isNot(contains(707)));
      expect(ratingRequests, hasLength(1));
      expect(
        ratingRequests.single['p_product_ids'],
        unorderedEquals(expectedProducts.keys),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
