import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saudi_factories/core/currency.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/core/theme.dart';
import 'package:saudi_factories/pages/user_type_page.dart';
import 'package:saudi_factories/widgets/bottom_nav.dart';
import 'package:saudi_factories/widgets/common.dart';
import 'package:saudi_factories/widgets/price_text.dart';
import 'package:saudi_factories/widgets/wordmark.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late ByteData testFont;
  late bool originalRuntimeFetching;

  setUpAll(() async {
    originalRuntimeFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    // Keep the real theme, sizes, weights and spacing; use Flutter's bundled
    // deterministic test font for every Tajawal weight. No network, developer
    // font cache or font download is required. This checks layout, not pixels.
    var directory = File(Platform.resolvedExecutable).parent;
    while (true) {
      final candidate = File(
        '${directory.path}/packages/flutter_tools/static/Ahem.ttf',
      );
      if (candidate.existsSync()) {
        testFont = ByteData.sublistView(await candidate.readAsBytes());
        break;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        throw StateError('Flutter test font Ahem.ttf could not be located.');
      }
      directory = parent;
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SFCurrency.instance.load();
    const variants = [
      'Thin',
      'ExtraLight',
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ];
    final manifest = <String, Object>{
      for (final weight in variants)
        'test-fonts/Tajawal-$weight.ttf': [
          {'asset': 'test-fonts/Tajawal-$weight.ttf'},
        ],
    };
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final asset = const StringCodec().decodeMessage(message);
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (asset?.startsWith('test-fonts/Tajawal-') == true) return testFont;
      return binding.defaultBinaryMessenger.delegate.send(
        'flutter/assets',
        message,
      );
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });
  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = originalRuntimeFetching;
  });

  for (final size in [const Size(320, 568), const Size(430, 800)]) {
    for (final scale in [1.0, 1.3]) {
      final scenario = '${size.width.toInt()}×${size.height.toInt()} / $scale';

      testWidgets('RTL header, badges and price remain usable: $scenario', (
        tester,
      ) async {
        _setViewport(tester, size);
        final i18n = I18n('ar');
        addTearDown(i18n.dispose);
        String? query;
        SFTab? destination;
        await tester.pumpWidget(
          _host(
            i18n: i18n,
            scale: scale,
            child: Scaffold(
              appBar: SFTopBar(
                titleWidget: const Wordmark(),
                searchHint: i18n.t('search_placeholder'),
                onSearchChanged: (value) => query = value,
              ),
              body: const Padding(
                padding: EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SFPriceText(
                      '33.00 – 44.00 ﷼',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              bottomNavigationBar: SFBottomNav(
                current: SFTab.home,
                unreadMessages: 101,
                cartCount: 120,
                onTap: (tab) => destination = tab,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('99+'), findsNWidgets(2));
        expect(find.byType(TextField).hitTestable(), findsOneWidget);
        expect(find.byType(SFPriceText).hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(TextField)).width, greaterThan(150));

        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel('Saudi Factories B2B'), findsOneWidget);
        expect(find.bySemanticsLabel('33.00 – 44.00 SAR'), findsOneWidget);
        semantics.dispose();

        await tester.enterText(find.byType(TextField), 'مصنع');
        expect(query, 'مصنع');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        for (final icon in [
          Icons.home_outlined,
          Icons.grid_view_outlined,
          Icons.factory_outlined,
          Icons.chat_bubble_outline,
          Icons.person_outline,
          Icons.shopping_cart_outlined,
        ]) {
          expect(find.byIcon(icon).hitTestable(), findsOneWidget);
        }
        await tester.tap(find.byIcon(Icons.shopping_cart_outlined));
        await tester.pumpAndSettle();
        expect(destination, SFTab.cart);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'RTL account choices and guest entry are reachable: $scenario',
        (tester) async {
          _setViewport(tester, size);
          final i18n = I18n('ar');
          addTearDown(i18n.dispose);
          await tester.pumpWidget(
            _host(i18n: i18n, scale: scale, child: const UserTypePage()),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final key in [
            'usertype_individual',
            'usertype_factory',
            'prod_browse_all',
          ]) {
            final action = find.text(i18n.t(key));
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            final rect = tester.getRect(action);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
          }
          // Guest navigation is deliberately not tapped: this is a layout test,
          // so it must not instantiate the authenticated data/network shell.
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final language in ['ar', 'en']) {
    testWidgets(
      'Floating navigation stays tappable above the home indicator: $language',
      (tester) async {
        const size = Size(320, 568);
        const bottomInset = 34.0;
        _setViewport(tester, size);
        final i18n = I18n(language);
        addTearDown(i18n.dispose);
        final semantics = tester.ensureSemantics();
        try {
          var current = SFTab.home;
          await tester.pumpWidget(
            _host(
              i18n: i18n,
              scale: 1.3,
              bottomPadding: bottomInset,
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  body: const SizedBox.expand(),
                  bottomNavigationBar: SFBottomNav(
                    current: current,
                    unreadMessages: 101,
                    cartCount: 120,
                    onTap: (tab) => setState(() => current = tab),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final capsule = tester.getRect(
            find.byKey(const Key('sf-bottom-nav-surface')),
          );
          expect(capsule.left, greaterThan(0));
          expect(capsule.right, lessThan(size.width));
          expect(capsule.bottom, lessThanOrEqualTo(size.height - bottomInset));
          expect(find.text('99+'), findsNWidgets(2));
          for (final badge in find.text('99+').evaluate()) {
            final bounds = tester.getRect(find.byWidget(badge.widget));
            expect(capsule.contains(bounds.topLeft), isTrue);
            expect(capsule.contains(bounds.bottomRight), isTrue);
          }

          double? previousCenter;
          for (final tab in SFTab.values) {
            final item = _navigationItem(i18n, tab);
            final target = find.descendant(
              of: item,
              matching: find.byType(InkWell),
            );
            expect(target.hitTestable(), findsOneWidget);
            final bounds = tester.getRect(target);
            expect(bounds.width, greaterThanOrEqualTo(44));
            expect(bounds.height, greaterThanOrEqualTo(44));
            expect(bounds.bottom, lessThanOrEqualTo(size.height - bottomInset));
            if (previousCenter != null) {
              expect(
                bounds.center.dx,
                i18n.isRtl
                    ? lessThan(previousCenter)
                    : greaterThan(previousCenter),
              );
            }
            previousCenter = bounds.center.dx;

            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(current, tab);
            for (final candidate in SFTab.values) {
              final flags = tester
                  .getSemantics(_navigationItem(i18n, candidate))
                  .flagsCollection;
              expect(flags.isButton, isTrue);
              expect(flags.isSelected.toBoolOrNull(), candidate == tab);
            }
            expect(tester.takeException(), isNull);
          }
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

Finder _navigationItem(I18n i18n, SFTab tab) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == i18n.t('nav_${tab.name}'),
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host({
  required I18n i18n,
  required double scale,
  required Widget child,
  double bottomPadding = 0,
}) {
  return I18nScope(
    i18n: i18n,
    child: MaterialApp(
      // The harness does not bundle GPU shader assets; changing only the tap
      // effect keeps production colors, typography and dimensions intact.
      theme: buildAppTheme().copyWith(splashFactory: InkRipple.splashFactory),
      builder: (context, body) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: EdgeInsets.only(bottom: bottomPadding),
          viewPadding: EdgeInsets.only(bottom: bottomPadding),
        ),
        child: Directionality(textDirection: i18n.direction, child: body!),
      ),
      home: child,
    ),
  );
}
