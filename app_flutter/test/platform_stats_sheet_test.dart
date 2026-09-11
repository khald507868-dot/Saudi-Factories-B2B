import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:saudi_factories/core/currency.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/widgets/platform_stats.dart';
import 'package:saudi_factories/widgets/price_text.dart';

const _trigger = ValueKey('open-platform-stats');
const _close = ValueKey('platform-stats-close');
const _scroll = ValueKey('platform-stats-scroll');
const _validRow = {
  'factories_count': 12,
  'products_count': 345,
  'units_sold': 6789,
  'revenue': 12345.67,
};

Widget _host({double textScale = 1, double bottomInset = 0}) => I18nScope(
  i18n: I18n('ar'),
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        padding: EdgeInsets.only(bottom: bottomInset),
        viewPadding: EdgeInsets.only(bottom: bottomInset),
      ),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: _trigger,
            onPressed: () => showPlatformStats(context),
            child: Text(context.t('stats_title')),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _settleRequest(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pumpAndSettle();
}

List<String> _values(WidgetTester tester) => tester
    .widgetList<SFPriceText>(find.byType(SFPriceText))
    .map((widget) => widget.text)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var requests = 0;
  var status = 200;
  Object? payload = [_validRow];
  Completer<http.Response>? pending;
  http.Request? lastRequest;

  http.Response response() => http.Response(
    jsonEncode(payload),
    status,
    request: lastRequest,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://platform-stats-test.invalid',
      publishableKey: 'test-public-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/get_public_stats');
        lastRequest = request;
        requests++;
        return pending == null ? response() : pending!.future;
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  setUp(() async {
    requests = 0;
    status = 200;
    payload = [_validRow];
    pending = null;
    lastRequest = null;
    SharedPreferences.setMockInitialValues({});
    await SFCurrency.instance.load();
  });

  testWidgets('الفتح وحده يطلب الأرقام مع تحميل واضح وإجمالي بالريال', (
    tester,
  ) async {
    final i18n = I18n('ar');
    pending = Completer<http.Response>();
    await SFCurrency.instance.setCurrency('USD');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(requests, 0);

    await tester.tap(find.byKey(_trigger));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(requests, 1);
    expect(find.text(i18n.t('fx_loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending!.complete(response());
    await _settleRequest(tester);
    expect(_values(tester), ['12', '345', '6789', '12,345.67 ﷼']);
    expect(tester.getSize(find.byKey(_scroll)).width, lessThanOrEqualTo(430));
    for (final key in [
      'stats_factories',
      'stats_products',
      'stats_units_sold',
      'stats_revenue',
    ]) {
      expect(find.text(i18n.t(key)), findsOneWidget);
    }

    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(find.byType(PlatformStats), findsNothing);
    expect(requests, 1);

    pending = null;
    payload = [
      {..._validRow, 'factories_count': 91},
    ];
    await tester.tap(find.byKey(_trigger));
    await _settleRequest(tester);
    expect(requests, 2);
    expect(_values(tester).first, '91');
    expect(tester.takeException(), isNull);
  });

  testWidgets('فشل الطلب يعرض إعادة المحاولة وتستعيد الأرقام عند النجاح', (
    tester,
  ) async {
    final i18n = I18n('ar');
    status = 403;
    payload = {'code': '42501', 'message': 'temporarily unavailable'};
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(_trigger));
    await _settleRequest(tester);
    expect(find.text(i18n.t('app_load_error')), findsOneWidget);
    expect(find.text(i18n.t('app_retry')), findsOneWidget);
    expect(_values(tester), isEmpty);
    expect(requests, 1);

    status = 200;
    payload = [_validRow];
    await tester.tap(find.text(i18n.t('app_retry')));
    await _settleRequest(tester);
    expect(requests, 2);
    expect(_values(tester), ['12', '345', '6789', '12,345.67 ﷼']);
    expect(find.text(i18n.t('app_load_error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('صفوف الخادم الناقصة وغير الصالحة لا تتحول إلى أصفار', (
    tester,
  ) async {
    final invalidRows = <Object?>[
      [],
      {},
      [
        {..._validRow, 'products_count': null},
      ],
      [
        {..._validRow, 'factories_count': -1},
      ],
      [
        {..._validRow, 'products_count': 1.5},
      ],
      [
        {..._validRow, 'revenue': 'NaN'},
      ],
    ];
    await tester.pumpWidget(_host());
    for (final invalid in invalidRows) {
      payload = invalid;
      await tester.tap(find.byKey(_trigger));
      await _settleRequest(tester);
      expect(find.text(I18n('ar').t('app_load_error')), findsOneWidget);
      expect(_values(tester), isEmpty);
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.byType(PlatformStats), findsNothing);
    }
    expect(requests, invalidRows.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('تبقى الأرقام والإغلاق متاحة بعرض320 مع النص المكبر', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(textScale: 2.5, bottomInset: 20));
    await tester.tap(find.byKey(_trigger));
    await _settleRequest(tester);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_scroll)).width, 320);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(_scroll),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    final revenueLabel = find.text(I18n('ar').t('stats_revenue'));
    await tester.ensureVisible(revenueLabel);
    await tester.pumpAndSettle();
    expect(revenueLabel.hitTestable(), findsOneWidget);
    expect(_values(tester).last, '12,345.67 ﷼');

    await tester.ensureVisible(find.byKey(_close));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(find.byType(PlatformStats), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
