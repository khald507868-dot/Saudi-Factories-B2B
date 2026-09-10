import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/widgets/bottom_nav.dart';

const _captureKey = ValueKey('glass-capture');
const _rowCount = 24;

Widget _host({
  required I18n i18n,
  required ScrollController scroll,
  required ValueNotifier<Color> contentColor,
  required ValueChanged<SFTab> onTap,
  double bottomInset = 0,
  double keyboardInset = 0,
  VoidCallback? onCheckout,
}) => I18nScope(
  i18n: i18n,
  child: MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: EdgeInsets.only(bottom: keyboardInset == 0 ? bottomInset : 0),
        viewPadding: EdgeInsets.only(bottom: bottomInset),
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: Directionality(textDirection: i18n.direction, child: child!),
    ),
    home: _GlassPage(
      scroll: scroll,
      contentColor: contentColor,
      onTap: onTap,
      onCheckout: onCheckout,
    ),
  ),
);

class _GlassPage extends StatefulWidget {
  const _GlassPage({
    required this.scroll,
    required this.contentColor,
    required this.onTap,
    this.onCheckout,
  });
  final ScrollController scroll;
  final ValueNotifier<Color> contentColor;
  final ValueChanged<SFTab> onTap;
  final VoidCallback? onCheckout;

  @override
  State<_GlassPage> createState() => _GlassPageState();
}

class _GlassPageState extends State<_GlassPage> {
  SFTab _current = SFTab.home;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: _captureKey,
    child: Scaffold(
      extendBody: true,
      body: widget.onCheckout == null
          ? _content()
          : Scaffold(
              body: _content(),
              bottomNavigationBar: SafeArea(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    key: const ValueKey('glass-checkout'),
                    onPressed: widget.onCheckout,
                    child: const Text('إتمام الطلب'),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: SFBottomNav(
        current: _current,
        unreadMessages: 101,
        cartCount: 7,
        onTap: (tab) {
          setState(() {
            _current = tab;
          });
          widget.onTap(tab);
        },
      ),
    ),
  );

  Widget _content() => Builder(
    // ListView يستفيد من padding الذي يضيفه Scaffold إلى MediaQuery.
    builder: (context) => ValueListenableBuilder<Color>(
      valueListenable: widget.contentColor,
      builder: (context, color, _) => ListView.builder(
        key: const ValueKey('glass-content'),
        controller: widget.scroll,
        itemCount: _rowCount,
        itemExtent: 100,
        itemBuilder: (_, index) => ColoredBox(
          key: ValueKey('glass-row-$index'),
          color: color,
          child: Center(child: Text('مصنع $index')),
        ),
      ),
    ),
  );
}

Finder _tab(I18n i18n, SFTab tab) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == i18n.t('nav_${tab.name}'),
);

Future<Color> _pixel(WidgetTester tester, Offset point) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final index = (point.dy.round() * image.width + point.dx.round()) * 4;
      return Color.fromARGB(
        bytes!.getUint8(index + 3),
        bytes.getUint8(index),
        bytes.getUint8(index + 1),
        bytes.getUint8(index + 2),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['ar', 'en']) {
    for (final bottomInset in [0.0, 24.0]) {
      testWidgets(
        'المحتوى يمر خلف الشريط وكل تبويباته وآخر صف قابلة للوصول: $language/$bottomInset',
        (tester) async {
          _viewport(tester);
          final i18n = I18n(language);
          final scroll = ScrollController();
          final contentColor = ValueNotifier(const Color(0xFFBAD8C5));
          addTearDown(i18n.dispose);
          addTearDown(scroll.dispose);
          addTearDown(contentColor.dispose);
          final semantics = tester.ensureSemantics();
          try {
            SFTab? selected;
            await tester.pumpWidget(
              _host(
                i18n: i18n,
                scroll: scroll,
                contentColor: contentColor,
                bottomInset: bottomInset,
                onTap: (tab) => selected = tab,
              ),
            );
            await tester.pumpAndSettle();

            final pill = tester.getRect(
              find.byKey(const ValueKey('sf-bottom-nav-surface')),
            );
            final content = tester.getRect(
              find.byKey(const ValueKey('glass-content')),
            );
            expect(pill.width, 284);
            expect(pill.height, 50);
            expect(pill.left, 18);
            expect(pill.bottom, lessThanOrEqualTo(700 - bottomInset));
            expect(content.bottom, 700);
            expect(content.overlaps(pill), isTrue);
            final firstUnderPill = tester.getRect(
              find.byKey(const ValueKey('glass-row-6')),
            );
            expect(firstUnderPill.overlaps(pill), isTrue);

            scroll.jumpTo(50);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.byKey(const ValueKey('glass-row-6'))).top,
              firstUnderPill.top - 50,
            );
            expect(
              tester.getRect(
                find.byKey(const ValueKey('sf-bottom-nav-surface')),
              ),
              pill,
            );
            expect(find.text('99+'), findsOneWidget);
            expect(find.text('7'), findsOneWidget);
            expect(
              tester.getSemantics(_tab(i18n, SFTab.messages)).value,
              '101',
            );
            expect(tester.getSemantics(_tab(i18n, SFTab.cart)).value, '7');

            double? previousX;
            for (final tab in SFTab.values) {
              final target = find.descendant(
                of: _tab(i18n, tab),
                matching: find.byType(InkWell),
              );
              expect(target.hitTestable(), findsOneWidget);
              final bounds = tester.getRect(target);
              expect(bounds.width, greaterThanOrEqualTo(44));
              expect(bounds.height, greaterThanOrEqualTo(40));
              if (previousX != null) {
                expect(
                  bounds.center.dx,
                  i18n.isRtl ? lessThan(previousX) : greaterThan(previousX),
                );
              }
              previousX = bounds.center.dx;
              await tester.tap(target);
              await tester.pumpAndSettle();
              expect(selected, tab);
              for (final candidate in SFTab.values) {
                final flags = tester
                    .getSemantics(_tab(i18n, candidate))
                    .flagsCollection;
                expect(flags.isButton, isTrue);
                expect(flags.isSelected.toBoolOrNull(), candidate == tab);
              }
            }

            scroll.jumpTo(scroll.position.maxScrollExtent);
            await tester.pumpAndSettle();
            final last = find.byKey(
              const ValueKey('glass-row-${_rowCount - 1}'),
            );
            expect(last.hitTestable(), findsOneWidget);
            expect(tester.getRect(last).bottom, lessThanOrEqualTo(pill.top));
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets('الزجاج يُظهر لون المحتوى خلفه فعلياً عند تغيّر الخلفية', (
    tester,
  ) async {
    _viewport(tester);
    final i18n = I18n('ar');
    final scroll = ScrollController();
    const red = Color(0xFFC62828);
    const blue = Color(0xFF1565C0);
    final contentColor = ValueNotifier(red);
    addTearDown(i18n.dispose);
    addTearDown(scroll.dispose);
    addTearDown(contentColor.dispose);
    await tester.pumpWidget(
      _host(
        i18n: i18n,
        scroll: scroll,
        contentColor: contentColor,
        onTap: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    // المنتصف يقع بين أيقونتين، بعيداً عن الكتابة وحدّ الكبسولة.
    final point = tester
        .getRect(find.byKey(const ValueKey('sf-bottom-nav-surface')))
        .center;
    final redUnderGlass = await _pixel(tester, point);
    contentColor.value = blue;
    await tester.pumpAndSettle();
    final blueUnderGlass = await _pixel(tester, point);
    expect(redUnderGlass.r - blueUnderGlass.r, greaterThan(.08));
    expect(blueUnderGlass.b - redUnderGlass.b, greaterThan(.08));
    expect(redUnderGlass, isNot(red));
    expect(blueUnderGlass, isNot(blue));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'زر إتمام الطلب داخل Scaffold ثانٍ يبقى فوق الشريط ولوحة المفاتيح',
    (tester) async {
      _viewport(tester);
      final i18n = I18n('ar');
      final scroll = ScrollController();
      final contentColor = ValueNotifier(const Color(0xFFBAD8C5));
      addTearDown(i18n.dispose);
      addTearDown(scroll.dispose);
      addTearDown(contentColor.dispose);
      var checkouts = 0;
      for (final keyboard in [0.0, 300.0]) {
        await tester.pumpWidget(
          _host(
            i18n: i18n,
            scroll: scroll,
            contentColor: contentColor,
            bottomInset: 24,
            keyboardInset: keyboard,
            onTap: (_) {},
            onCheckout: () => checkouts++,
          ),
        );
        await tester.pumpAndSettle();
        final checkout = find.byKey(const ValueKey('glass-checkout'));
        final bounds = tester.getRect(checkout);
        final pill = tester.getRect(
          find.byKey(const ValueKey('sf-bottom-nav-surface')),
        );
        expect(checkout.hitTestable(), findsOneWidget);
        expect(bounds.bottom, lessThanOrEqualTo(pill.top));
        expect(bounds.bottom, lessThanOrEqualTo(700 - keyboard));
        await tester.tap(checkout);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(checkouts, 2);
    },
  );
}
