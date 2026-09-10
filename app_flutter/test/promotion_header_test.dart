import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/core/theme.dart';
import 'package:saudi_factories/services/delivery_address_service.dart';
import 'package:saudi_factories/services/promotion_service.dart';
import 'package:saudi_factories/widgets/common.dart';
import 'package:saudi_factories/widgets/delivery_address_widgets.dart';
import 'package:saudi_factories/widgets/home_promotions.dart';

const _first = SFPromotion(
  id: 'header-first',
  title: 'العرض الأول',
  imageUrl: 'https://example.com/header-first.png',
);
const _second = SFPromotion(
  id: 'header-second',
  title: 'العرض الثاني',
  imageUrl: 'https://example.com/header-second.png',
);
const _hidden = SFPromotion(
  id: 'header-second',
  title: 'العرض الثاني',
  imageUrl: 'https://example.com/header-second.png',
  isActive: false,
);

Widget _host(Widget child, {String language = 'ar'}) => I18nScope(
  i18n: I18n(language),
  child: MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    builder: (context, child) => Directionality(
      textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: child!,
    ),
    home: child,
  ),
);

Future<void> _cacheBanner(WidgetTester tester, String url, Color color) async {
  final image = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 50), Paint()..color = color);
    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 50);
    picture.dispose();
    return image;
  });
  final key = await NetworkImage(url).obtainKey(ImageConfiguration.empty);
  // مفتاح الصورة مطابق لـImage.network؛ لا تخرج أي طلبات إلى الشبكة.
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
  );
  await tester.pump();
}

Future<void> _settleImage(WidgetTester tester) async {
  // toImage ثم toByteData يعبران ساعة المحرك الحقيقية على مرحلتين.
  for (var phase = 0; phase < 3; phase++) {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('غياب الإعلانات يعيد ترويسة الزائر إلى الأبيض', (tester) async {
    final colors = <Color>[];
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: HomePromotions(
            promotions: Future.value(const [_hidden]),
            onRetry: () {},
            onBackgroundColorChanged: colors.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(colors, isNotEmpty);
    expect(colors.last, SFColors.white);
    expect(find.byType(PromotionCarousel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('مساحة إضافة الإعلان تعطي ترويسة المدير لونها الفاتح', (
    tester,
  ) async {
    final colors = <Color>[];
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: HomePromotions(
            promotions: Future.value(const []),
            onRetry: () {},
            onManage: () {},
            onBackgroundColorChanged: colors.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(colors.last, SFColors.surfaceAlt);
    expect(find.text('أضف إعلان تخفيضات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('لون الترويسة يتبع الإعلان الظاهر ويعود للأبيض بعد إخفائه', (
    tester,
  ) async {
    const firstColor = Color(0xFFFFD740);
    const secondColor = Color(0xFF123D29);
    await _cacheBanner(tester, _first.imageUrl, firstColor);
    await _cacheBanner(tester, _second.imageUrl, secondColor);
    final colors = <Color>[];
    Widget promotions(List<SFPromotion> items) => _host(
      Scaffold(
        body: HomePromotions(
          promotions: Future.value(items),
          onRetry: () {},
          onBackgroundColorChanged: colors.add,
        ),
      ),
    );
    await tester.pumpWidget(promotions(const [_first, _second]));
    await _settleImage(tester);
    expect(colors.last, firstColor);

    await tester.tap(find.byType(InkResponse).last);
    await _settleImage(tester);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 1);
    expect(colors.last, secondColor);

    await tester.pumpWidget(promotions(const [_hidden]));
    await _settleImage(tester);
    expect(find.byType(PromotionCarousel), findsNothing);
    expect(colors.last, SFColors.white);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ar', 'en']) {
    testWidgets(
      'البحث والعنوان يعملان فوق ترويسة ملونة بارتفاع84 وعرض320: $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final addresses = DeliveryAddressService.forTesting(
          preferences: SharedPreferences.getInstance,
          userId: () => null,
        );
        addTearDown(addresses.dispose);
        await addresses.start();
        String? submitted;
        final topBar = SFTopBar(
          compact: true,
          toolbarHeight: 44,
          backgroundColor: SFColors.darkGreen,
          searchBackgroundColor: SFColors.white,
          showBottomBorder: false,
          titleWidget: DeliveryAddressHeader(
            service: addresses,
            foregroundColor: SFColors.white,
          ),
          searchHint: I18n(language).t('search_placeholder'),
          onSearchSubmitted: (value) => submitted = value,
        );
        await tester.pumpWidget(
          _host(
            Scaffold(appBar: topBar, body: const SizedBox.expand()),
            language: language,
          ),
        );
        await tester.pumpAndSettle();
        expect(topBar.preferredSize.height, 84);
        expect(tester.getSize(find.byType(SFTopBar)), const Size(320, 84));
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.backgroundColor, SFColors.darkGreen);
        final searchFrame = tester.widget<Container>(
          find
              .ancestor(
                of: find.byType(TextField),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Container && widget.decoration is BoxDecoration,
                ),
              )
              .first,
        );
        expect(
          (searchFrame.decoration! as BoxDecoration).color,
          SFColors.white,
        );
        final addressLabel = tester.widget<Text>(
          find
              .descendant(
                of: find.byType(DeliveryAddressHeader),
                matching: find.byType(Text),
              )
              .first,
        );
        expect(addressLabel.style?.color, SFColors.white);

        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'مصنع الرياض');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(submitted, 'مصنع الرياض');

        await tester.tap(
          find.byKey(const ValueKey('delivery-address-trigger')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DeliveryAddressSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
