import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/pages/home_page.dart';
import 'package:saudi_factories/services/promotion_service.dart';
import 'package:saudi_factories/widgets/home_promotions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var published = false;
  var reads = 0;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://home-promotions-test.invalid',
      publishableKey: 'test-public-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        final rows = <Map<String, dynamic>>[];
        if (request.url.path == '/rest/v1/home_promotions') {
          reads++;
          if (published) {
            rows.add({
              'id': '11111111-1111-4111-8111-111111111111',
              'title': 'إعلان جديد',
              'image_url': 'https://example.com/banner.png',
              'target_url': '',
              'is_active': true,
              'sort_order': 0,
            });
          }
        }
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets(
    'الرئيسية تتحدث بعد نشر الإعلان وإخفائه وتزيل مستمعها عند الإغلاق',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        I18nScope(
          i18n: I18n('ar'),
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            builder: (context, child) =>
                Directionality(textDirection: TextDirection.rtl, child: child!),
            home: const HomePage(),
          ),
        ),
      );
      // نترك قراءة ملف الخريطة وطلبات العميل الوهمي تنتهي خارج الساعة المزيفة.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.byType(PromotionCarousel), findsNothing);
      expect(reads, 1);

      published = true;
      PromotionService.changes.value++;
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.byType(PromotionCarousel), findsOneWidget);
      expect(reads, 2);

      published = false;
      PromotionService.changes.value++;
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.byType(PromotionCarousel), findsNothing);
      expect(reads, 3);

      await tester.pumpWidget(const SizedBox.shrink());
      PromotionService.changes.value++;
      await tester.pumpAndSettle();
      expect(reads, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
