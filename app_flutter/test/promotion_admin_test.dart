import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/core/supabase_config.dart';
import 'package:saudi_factories/services/auth_service.dart';
import 'package:saudi_factories/widgets/promotion_admin.dart';

const _uid = '11111111-1111-4111-8111-111111111111';
const _image =
    '$kSupabaseUrl/storage/v1/object/public/promotion-media/$_uid/banners/test.png';

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget _host() => I18nScope(
  i18n: I18n('ar'),
  child: MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const Scaffold(body: PromotionAdmin()),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var isAdmin = true;
  var reads = 0;
  var writes = 0;
  var failSave = false;
  var failLoad = false;
  Completer<http.Response>? pendingSave;
  late Map<String, dynamic> row;
  late Map<String, dynamic> lastWrite;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://promotions-test.invalid',
      publishableKey: 'test-public-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        Future<http.Response> respond() async {
          final path = request.url.path;
          if (path == '/auth/v1/token') {
            final payload = base64Url
                .encode(
                  utf8.encode(jsonEncode({'sub': _uid, 'exp': 4102444800})),
                )
                .replaceAll('=', '');
            return _json({
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test',
              'refresh_token': 'test-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': _uid,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'admin@example.test',
                'app_metadata': <String, dynamic>{},
                'user_metadata': <String, dynamic>{},
                'created_at': '2026-01-01T00:00:00Z',
              },
            });
          }
          if (path == '/auth/v1/logout') return http.Response('', 204);
          if (path == '/rest/v1/profiles') {
            return _json({'is_admin': isAdmin, 'full_name': 'مدير الموقع'});
          }
          if (path == '/rest/v1/home_promotions') {
            if (request.method == 'GET') {
              reads++;
              if (failLoad) {
                return _json({
                  'message': 'setup missing',
                  'code': '42P01',
                }, 404);
              }
              return _json([row]);
            }
            writes++;
            lastWrite = jsonDecode(request.body) as Map<String, dynamic>;
            if (pendingSave != null) return pendingSave!.future;
            if (failSave) {
              return _json({
                'message': 'test save failure',
                'code': '23514',
              }, 400);
            }
            row = {...row, ...lastWrite};
            return _json(row);
          }
          throw StateError(
            'Unexpected mocked request: ${request.method} $path',
          );
        }

        final response = await respond();
        // PostgREST reads the original method and Accept header from request.
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
  });

  setUp(() {
    isAdmin = true;
    reads = 0;
    writes = 0;
    failSave = false;
    failLoad = false;
    pendingSave = null;
    lastWrite = {};
    row = {
      'id': '22222222-2222-4222-8222-222222222222',
      'title': 'عرض سابق',
      'image_url': _image,
      'target_url': '',
      'is_active': false,
      'sort_order': 0,
    };
  });

  tearDown(() async {
    if (AuthService.instance.isSignedIn) await AuthService.instance.signOut();
  });

  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> openAdmin(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => AuthService.instance.signIn('admin@example.test', 'test-only'),
    );
    expect(AuthService.instance.profile?.isAdmin, isTrue);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
  }

  testWidgets('الزائر والحساب العادي لا يطلبان بيانات إدارة الإعلانات', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('إدارة الإعلانات متاحة لمدير الموقع فقط'), findsOneWidget);
    expect(reads, 0);
    expect(find.text('إضافة إعلان'), findsNothing);

    isAdmin = false;
    await tester.runAsync(
      () => AuthService.instance.signIn('user@example.test', 'test-only'),
    );
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(writes, 0);
    expect(find.text('إضافة إعلان'), findsNothing);
  });

  testWidgets(
    'فشل التحميل يعرض إعادة المحاولة ويمنع رفع إعلان قبل تهيئة الخدمة',
    (tester) async {
      failLoad = true;
      await openAdmin(tester);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      final add = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'إضافة إعلان'),
      );
      expect(add.onPressed, isNull);
      failLoad = false;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(find.text('عرض سابق'), findsOneWidget);
      expect(reads, 2);
    },
  );

  testWidgets('الإعلان المخفي يظهر للمدير ويمكن نشره من المفتاح', (
    tester,
  ) async {
    await openAdmin(tester);
    expect(find.text('مخفي'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(lastWrite, {'is_active': true});
    expect(writes, 1);
    expect(find.text('ظاهر للزوار'), findsOneWidget);
  });

  testWidgets('فشل الحفظ يحتفظ بالقيم وإعادة الحفظ تنجح وتغلق المحرر', (
    tester,
  ) async {
    await openAdmin(tester);
    await tester.tap(find.text('تعديل الإعلان'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'عرض جديد');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'https://example.test/offer',
    );
    await tester.enterText(find.byType(TextFormField).at(2), '3');
    failSave = true;
    await tester.ensureVisible(find.text('حفظ الإعلان'));
    await tester.tap(find.text('حفظ الإعلان'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('عرض جديد'), findsOneWidget);
    expect(find.text('https://example.test/offer'), findsOneWidget);
    expect(find.text('تعذّر تنفيذ العملية.'), findsOneWidget);
    expect(writes, 1);

    failSave = false;
    await tester.tap(find.text('حفظ الإعلان'));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('عرض جديد'), findsOneWidget);
    expect(lastWrite['sort_order'], 3);
    expect(lastWrite['is_active'], false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الحفظ المعلّق لا يتكرر ولا يسمح بإغلاق المحرر قبل اكتماله', (
    tester,
  ) async {
    await openAdmin(tester);
    await tester.tap(find.text('تعديل الإعلان'));
    await tester.pumpAndSettle();
    pendingSave = Completer<http.Response>();
    await tester.ensureVisible(find.text('حفظ الإعلان'));
    await tester.tap(find.text('حفظ الإعلان'));
    await tester.pump();
    await tester.pump();
    expect(writes, 1);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'حفظ الإعلان'),
    );
    expect(save.onPressed, isNull);
    await tester.tap(find.text('حفظ الإعلان'));
    await tester.pump();
    expect(writes, 1);
    await tester.pageBack();
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(3));
    pendingSave!.complete(_json({...row, ...lastWrite}));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الإعلان الجديد يحتاج صورة والرابط غير الآمن لا يرسل أي كتابة', (
    tester,
  ) async {
    await openAdmin(tester);
    await tester.tap(find.text('إضافة إعلان'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'خصم جديد');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'javascript:alert(1)',
    );
    await tester.ensureVisible(find.text('حفظ الإعلان'));
    await tester.tap(find.text('حفظ الإعلان'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('ارفع صورة للإعلان أولاً'), findsOneWidget);
    expect(find.text('أدخل رابطاً صحيحاً يبدأ بـ https://'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
  });
}
