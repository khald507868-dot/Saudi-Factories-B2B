import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/services/delivery_address_service.dart';
import 'package:saudi_factories/widgets/delivery_address_widgets.dart';
import 'package:saudi_factories/widgets/home_header.dart';

const _bannerColor = Color(0xFF285F3B);
const _safeTop = 24.0;

Widget _host({
  required ScrollController scroll,
  required String language,
  required ValueChanged<String> onSearch,
  required VoidCallback onStatsPressed,
}) => I18nScope(
  i18n: I18n(language),
  child: MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: _safeTop),
        viewPadding: const EdgeInsets.only(top: _safeTop),
      ),
      child: Directionality(
        textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: HomeHeader(
          scrollController: scroll,
          promotionColor: _bannerColor,
          searchHint: context.t('search_placeholder'),
          onSearchSubmitted: onSearch,
          onStatsPressed: onStatsPressed,
        ),
        body: ListView.builder(
          key: const ValueKey('home-scroll-content'),
          controller: scroll,
          padding: EdgeInsets.only(
            top: HomeHeader.height + MediaQuery.paddingOf(context).top,
          ),
          itemExtent: 96,
          itemCount: 24,
          itemBuilder: (_, index) => ColoredBox(
            key: ValueKey('home-content-$index'),
            color: index.isEven ? const Color(0xFFBAD8C5) : Colors.white,
            child: Center(child: Text('مصنع $index')),
          ),
        ),
      ),
    ),
  ),
);

Color _background(WidgetTester tester) => tester
    .widget<ColoredBox>(find.byKey(const ValueKey('home-header-background')))
    .color;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() => DeliveryAddressService.instance.dispose());

  testWidgets(
    'الترويسة تثبت وتشفّ أثناء التمرير وتبقى عناصرها فعالة بالعربية والإنجليزية',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await DeliveryAddressService.instance.start();
      // الخدمـة مفردة؛ تبديل اللغتين في دورة حياة واحدة يمنع تداخل ساعات الاختبار.
      for (final language in ['ar', 'en']) {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        String? submitted;
        var statsPresses = 0;
        await tester.pumpWidget(
          _host(
            scroll: scroll,
            language: language,
            onSearch: (query) => submitted = query,
            onStatsPressed: () => statsPresses++,
          ),
        );
        await tester.pumpAndSettle();

        final headerRect = tester.getRect(find.byType(HomeHeader));
        expect(headerRect.width, 320);
        expect(headerRect.top, 0);
        expect(headerRect.height, 84 + _safeTop);
        expect(
          tester
              .widget<HomeHeader>(find.byType(HomeHeader))
              .preferredSize
              .height,
          84,
        );
        expect(_background(tester), _bannerColor);
        expect(
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
          isFalse,
        );
        final content = find.byKey(const ValueKey('home-scroll-content'));
        expect(tester.getTopLeft(content).dy, 0);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('home-content-0'))).dy,
          headerRect.bottom,
        );
        final address = find.byKey(const ValueKey('delivery-address-trigger'));
        expect(tester.getTopLeft(address).dy, greaterThanOrEqualTo(_safeTop));
        final stats = find.byKey(const ValueKey('home-stats-trigger'));
        expect(stats, findsOneWidget);
        final statsRect = tester.getRect(stats);
        expect(statsRect.width, greaterThanOrEqualTo(44));
        expect(statsRect.height, greaterThanOrEqualTo(44));
        expect(
          statsRect.left,
          greaterThanOrEqualTo(tester.getRect(address).right),
        );
        expect(statsRect.right, lessThanOrEqualTo(headerRect.right));
        expect(statsRect.top, greaterThanOrEqualTo(_safeTop));
        await tester.tap(stats);
        await tester.pumpAndSettle();
        expect(statsPresses, 1);

        scroll.jumpTo(50);
        await tester.pumpAndSettle();
        final partial = _background(tester);
        expect(partial, isNot(_bannerColor));
        expect(partial.a, lessThan(1));
        expect(tester.getRect(find.byType(HomeHeader)), headerRect);
        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
          isTrue,
        );
        final partialBlur = tester
            .widget<BackdropFilter>(find.byType(BackdropFilter))
            .filter;

        scroll.jumpTo(100);
        await tester.pumpAndSettle();
        final scrolled = _background(tester);
        expect(scrolled.a, closeTo(.78, .01));
        expect(scrolled.r, closeTo(1, .001));
        expect(scrolled.g, closeTo(1, .001));
        expect(scrolled.b, closeTo(1, .001));
        expect(scrolled, isNot(partial));
        expect(
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
          isNot(partialBlur),
        );
        expect(tester.getRect(find.byType(HomeHeader)), headerRect);
        final firstRowTop = tester
            .getTopLeft(find.byKey(const ValueKey('home-content-0')))
            .dy;
        expect(firstRowTop, headerRect.bottom - 100);
        expect(firstRowTop, lessThan(headerRect.bottom));

        scroll.jumpTo(220);
        await tester.pumpAndSettle();
        expect(_background(tester), scrolled);
        expect(tester.getRect(find.byType(HomeHeader)), headerRect);
        expect(tester.getRect(stats), statsRect);
        await tester.tap(stats);
        await tester.pumpAndSettle();
        expect(statsPresses, 2);

        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'حديد');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(submitted, 'حديد');
        await tester.tap(address);
        await tester.pumpAndSettle();
        expect(find.byType(DeliveryAddressSheet), findsOneWidget);
        Navigator.of(tester.element(find.byType(DeliveryAddressSheet))).pop();
        await tester.pumpAndSettle();

        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(_background(tester), _bannerColor);
        expect(tester.getRect(find.byType(HomeHeader)), headerRect);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('home-content-0'))).dy,
          headerRect.bottom,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
