import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/pages/delivery_address_page.dart';
import 'package:saudi_factories/services/delivery_address_service.dart';
import 'package:saudi_factories/services/delivery_location_service.dart';
import 'package:saudi_factories/widgets/delivery_address_widgets.dart';

const _point = DeliveryLocation(
  latitude: 24.7,
  longitude: 46.7,
  addressLine: 'الرياض، طريق الملك فهد',
);

DeliveryAddress _address(String id, String label) => DeliveryAddress(
  id: id,
  label: label,
  addressLine: _point.addressLine,
  latitude: _point.latitude,
  longitude: _point.longitude,
);

DeliveryAddressService _store({
  bool failWrites = false,
  ValueNotifier<String?>? user,
}) {
  final service = DeliveryAddressService.forTesting(
    preferences: SharedPreferences.getInstance,
    userId: () => user?.value,
    authChanges: user,
    writeString: failWrites ? (_, _, _) async => false : null,
  );
  addTearDown(service.dispose);
  return service;
}

Widget _host(Widget child, {String lang = 'ar'}) => I18nScope(
  i18n: I18n(lang),
  child: MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    builder: (context, child) => Directionality(
      textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: child!,
    ),
    home: child,
  ),
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final lang in ['ar', 'en']) {
    testWidgets('اختيار عنوان من القائمة يحدّث العنوان أعلى الصفحة: $lang', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _store();
      await service.start();
      await service.save(_address('one', 'المنزل'));
      await service.save(_address('two', 'المستودع'));
      await tester.pumpWidget(
        _host(
          Scaffold(body: DeliveryAddressHeader(service: service)),
          lang: lang,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('المستودع'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delivery-address-trigger')));
      await tester.pumpAndSettle();
      expect(find.byType(DeliveryAddressSheet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delivery-address-one')));
      await tester.pumpAndSettle();
      expect(service.selected?.label, 'المنزل');
      expect(find.byType(DeliveryAddressSheet), findsNothing);
      expect(find.text('المنزل'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('حفظ تفاصيل الموقع يرجع من الصفحة ويحتفظ بالطابق والملاحظات', (
    tester,
  ) async {
    final service = _store();
    await service.start();
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DeliveryAddressPage(service: service, location: _point),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('delivery_label')),
      'المستودع',
    );
    await tester.enterText(find.byKey(const ValueKey('delivery_floor')), '2');
    await tester.enterText(
      find.byKey(const ValueKey('delivery_notes')),
      'البوابة الشرقية',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('delivery-save-address')),
    );
    expect(find.byType(DeliveryAddressPage), findsNothing);
    expect(service.selected?.addressLine, _point.addressLine);
    expect(service.selected?.floor, '2');
    expect(service.selected?.notes, 'البوابة الشرقية');
    expect(tester.takeException(), isNull);
  });

  testWidgets('الحقل المطلوب يمنع الحفظ وفشل التخزين يبقي المسودة', (
    tester,
  ) async {
    final service = _store(failWrites: true);
    await service.start();
    await tester.pumpWidget(
      _host(DeliveryAddressPage(service: service, location: _point)),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('delivery-save-address')),
    );
    expect(service.addresses, isEmpty);
    expect(find.text('هذا الحقل مطلوب'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('delivery_label')));
    await tester.enterText(
      find.byKey(const ValueKey('delivery_label')),
      'المنزل',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('delivery-save-address')),
    );
    expect(find.byType(DeliveryAddressPage), findsOneWidget);
    expect(service.addresses, isEmpty);
    expect(find.text('تعذّر حفظ العنوان، حاول مرة أخرى'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('delivery_label')))
          .controller
          ?.text,
      'المنزل',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'تبديل الحساب أثناء التحرير يحجب المسودة ويمنع حفظها للحساب التالي',
    (tester) async {
      final user = ValueNotifier<String?>(null);
      addTearDown(user.dispose);
      final service = _store(user: user);
      await service.start();
      await tester.pumpWidget(
        _host(DeliveryAddressPage(service: service, location: _point)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('delivery_label')),
        'عنوان خاص',
      );
      user.value = '10000000-0000-4000-8000-000000000001';
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('delivery_label')), findsNothing);
      expect(find.byKey(const ValueKey('delivery-save-address')), findsNothing);
      expect(service.addresses, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
