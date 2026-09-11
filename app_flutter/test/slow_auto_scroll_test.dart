import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saudi_factories/widgets/slow_auto_scroll.dart';

const _stripKey = ValueKey('auto-scroll-strip');

Widget _host({
  required ValueChanged<ScrollController> onController,
  TextDirection direction = TextDirection.ltr,
  bool enabled = true,
  bool reducedMotion = false,
  bool tickerEnabled = true,
  int itemCount = 10,
  double width = 320,
  ValueChanged<int>? onTap,
  FocusNode? firstItemFocus,
  GlobalKey<NavigatorState>? navigatorKey,
  ScrollController? verticalController,
}) {
  final strip = SizedBox(
    width: width,
    height: 100,
    child: TickerMode(
      enabled: tickerEnabled,
      child: SlowAutoScroll(
        enabled: enabled,
        builder: (context, controller) {
          onController(controller);
          return ListView.builder(
            key: _stripKey,
            controller: controller,
            scrollDirection: Axis.horizontal,
            itemExtent: 100,
            itemCount: itemCount,
            itemBuilder: (context, index) => InkWell(
              key: ValueKey('auto-scroll-item-$index'),
              focusNode: index == 0 ? firstItemFocus : null,
              onTap: () => onTap?.call(index),
              child: Center(child: Text('Product $index')),
            ),
          );
        },
      ),
    ),
  );
  return MaterialApp(
    navigatorKey: navigatorKey,
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
      body: verticalController == null
          ? Align(alignment: Alignment.topCenter, child: strip)
          : ListView(
              controller: verticalController,
              children: [
                Center(child: strip),
                const SizedBox(height: 1800),
              ],
            ),
    ),
  );
}

Future<void> _advance(WidgetTester tester, Duration duration) async {
  // إطارات متتابعة بدل pumpAndSettle لأن الحركة التلقائية مستمرة.
  final steps = (duration.inMilliseconds / 20).ceil();
  for (var index = 0; index < steps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
  expect(tester.takeException(), isNull);
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.binding.hasScheduledFrame, isFalse);
}

void main() {
  for (final direction in [TextDirection.rtl, TextDirection.ltr]) {
    testWidgets('حركة بطيئة باتجاه $direction مع بقاء البطاقة قابلة للنقر', (
      tester,
    ) async {
      late ScrollController controller;
      int? tapped;
      await tester.pumpWidget(
        _host(
          direction: direction,
          onController: (value) => controller = value,
          onTap: (index) => tapped = index,
        ),
      );
      await tester.pump();
      final item = find.byKey(const ValueKey('auto-scroll-item-1'));
      final before = tester.getCenter(item).dx;
      final initialOffset = controller.offset;
      await _advance(tester, const Duration(seconds: 2));
      expect(controller.offset - initialOffset, closeTo(24, 1));
      final after = tester.getCenter(item).dx;
      expect(
        direction == TextDirection.rtl ? after - before : before - after,
        closeTo(24, 1),
      );
      await tester.tap(item);
      await tester.pump();
      expect(tapped, 1);
      await _dispose(tester);
    });
  }

  testWidgets(
    'الضغط الثابت لا يوقف الحركة والسحب اليدوي يستأنفها فور انتهائه',
    (tester) async {
      late ScrollController controller;
      await tester.pumpWidget(
        _host(onController: (value) => controller = value),
      );
      await _advance(tester, const Duration(seconds: 1));
      final beforeTouch = controller.offset;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_stripKey)),
      );
      await _advance(tester, const Duration(seconds: 2));
      expect(controller.offset - beforeTouch, closeTo(24, 1));
      final beforeDrag = controller.offset;
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      final dragging = controller.offset;
      expect(dragging, greaterThan(beforeDrag + 30));
      await _advance(tester, const Duration(milliseconds: 200));
      expect(controller.offset, closeTo(dragging, .01));
      await gesture.up();
      await tester.pump();
      final afterDrag = controller.offset;
      await _advance(tester, const Duration(seconds: 1));
      expect(controller.offset - afterDrag, closeTo(12, 1));
      await _dispose(tester);
    },
  );

  testWidgets('القائمة تعكس اتجاهها عند الطرفين فورًا دون توقف أو قفزة', (
    tester,
  ) async {
    late ScrollController controller;
    await tester.pumpWidget(
      _host(
        width: 380,
        itemCount: 4,
        onController: (value) => controller = value,
      ),
    );
    final end = controller.position.maxScrollExtent;
    expect(end, 20);
    for (var frame = 0; frame < 120 && controller.offset < end; frame++) {
      final previous = controller.offset;
      await tester.pump(const Duration(milliseconds: 20));
      expect(controller.offset - previous, inInclusiveRange(0, .25));
    }
    expect(controller.offset, closeTo(end, .01));
    await tester.pump(const Duration(milliseconds: 20));
    expect(end - controller.offset, closeTo(.24, .02));
    final returning = controller.offset;
    await _advance(tester, const Duration(milliseconds: 500));
    expect(returning - controller.offset, closeTo(6, .5));
    for (var frame = 0; frame < 120 && controller.offset > 0; frame++) {
      final previous = controller.offset;
      await tester.pump(const Duration(milliseconds: 20));
      expect(previous - controller.offset, inInclusiveRange(0, .25));
    }
    expect(controller.offset, closeTo(0, .01));
    await tester.pump(const Duration(milliseconds: 20));
    expect(controller.offset, closeTo(.24, .02));
    await _dispose(tester);
  });

  testWidgets('التعطيل وتقليل الحركة وعدم وجود محتوى زائد تمنع التمرير', (
    tester,
  ) async {
    for (final scenario in [
      'disabled',
      'reduced-motion',
      'no-overflow',
      'ticker',
    ]) {
      late ScrollController controller;
      await tester.pumpWidget(
        _host(
          enabled: scenario != 'disabled',
          reducedMotion: scenario == 'reduced-motion',
          tickerEnabled: scenario != 'ticker',
          itemCount: scenario == 'no-overflow' ? 2 : 10,
          onController: (value) => controller = value,
        ),
      );
      await _advance(tester, const Duration(seconds: 5));
      expect(controller.offset, 0, reason: scenario);
      await _dispose(tester);
    }
  });

  testWidgets('المؤشر الساكن وتركيز البطاقة لا يوقفان الحركة البطيئة', (
    tester,
  ) async {
    late ScrollController controller;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(firstItemFocus: focus, onController: (value) => controller = value),
    );
    await _advance(tester, const Duration(seconds: 1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 300));
    await mouse.moveTo(tester.getCenter(find.byKey(_stripKey)));
    await tester.pump();
    final hovered = controller.offset;
    await _advance(tester, const Duration(seconds: 2));
    expect(controller.offset - hovered, closeTo(24, 1));

    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    final focused = controller.offset;
    await _advance(tester, const Duration(seconds: 2));
    expect(controller.offset - focused, closeTo(24, 1));
    expect(focus.hasFocus, isTrue);
    await mouse.removePointer();
    await _dispose(tester);
  });

  testWidgets('تستمر الحركة أثناء نقرة الماوس وبعدها مع بقاء المؤشر والتركيز', (
    tester,
  ) async {
    late ScrollController controller;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var taps = 0;
    await tester.pumpWidget(
      _host(
        firstItemFocus: focus,
        onController: (value) => controller = value,
        onTap: (index) {
          expect(index, 0);
          taps++;
          focus.requestFocus();
        },
      ),
    );
    await _advance(tester, const Duration(seconds: 1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 300));
    final card = tester.getCenter(
      find.byKey(const ValueKey('auto-scroll-item-0')),
    );
    await mouse.moveTo(card);
    final beforeClick = controller.offset;
    await mouse.down(card);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset - beforeClick, closeTo(1.2, .3));
    await mouse.up();
    await tester.pump();
    expect(taps, 1);
    expect(focus.hasFocus, isTrue);
    final afterClick = controller.offset;
    await _advance(tester, const Duration(seconds: 1));
    expect(controller.offset - afterClick, closeTo(12, 1));
    expect(focus.hasFocus, isTrue);
    final resumed = controller.offset;
    await _advance(tester, const Duration(seconds: 2));
    expect(controller.offset - resumed, closeTo(24, 1));
    expect(focus.hasFocus, isTrue);
    expect(taps, 1);
    await mouse.removePointer();
    await _dispose(tester);
  });

  testWidgets('الحركة البطيئة تتبع تمرير عجلة الفأرة فورًا', (tester) async {
    late ScrollController controller;
    await tester.pumpWidget(_host(onController: (value) => controller = value));
    await _advance(tester, const Duration(seconds: 1));
    final beforeWheel = controller.offset;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(_stripKey)),
        scrollDelta: const Offset(45, 0),
      ),
    );
    await tester.pump();
    final afterWheel = controller.offset;
    expect(afterWheel, greaterThan(beforeWheel));
    await _advance(tester, const Duration(seconds: 1));
    expect(controller.offset - afterWheel, closeTo(12, 1));
    await _dispose(tester);
  });

  testWidgets('فقدان تركيز النافذة يبقي الحركة وإخفاؤها يوقفها حتى الرجوع', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    late ScrollController controller;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(
        navigatorKey: navigator,
        onController: (value) => controller = value,
      ),
    );
    await _advance(tester, const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final inactive = controller.offset;
    await _advance(tester, const Duration(seconds: 2));
    expect(controller.offset - inactive, closeTo(24, 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    final hidden = controller.offset;
    await _advance(tester, const Duration(seconds: 5));
    expect(controller.offset, closeTo(hidden, .01));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _advance(tester, const Duration(seconds: 1));
    expect(controller.offset - hidden, closeTo(12, 1));

    navigator.currentState!.push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, _, _) => const Center(child: Text('Covered')),
      ),
    );
    await _advance(tester, const Duration(milliseconds: 400));
    final covered = controller.offset;
    await _advance(tester, const Duration(seconds: 5));
    expect(controller.offset, closeTo(covered, .01));
    navigator.currentState!.pop();
    await _advance(tester, const Duration(seconds: 1));
    expect(controller.offset, greaterThan(covered));
    expect(controller.offset - covered, lessThanOrEqualTo(13));
    await _dispose(tester);
  });

  testWidgets('التمرير العمودي يبقي الشريط متحركًا حتى يخرج من الشاشة', (
    tester,
  ) async {
    late ScrollController controller;
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _host(
        verticalController: vertical,
        onController: (value) => controller = value,
      ),
    );
    await _advance(tester, const Duration(seconds: 1));
    final before = controller.offset;
    final scrollDone = vertical.animateTo(
      40,
      duration: const Duration(seconds: 1),
      curve: Curves.linear,
    );
    await _advance(tester, const Duration(milliseconds: 1100));
    await scrollDone;
    expect(controller.offset - before, closeTo(13.2, 1));
    expect(tester.getBottomLeft(find.byKey(_stripKey)).dy, greaterThan(0));
    vertical.jumpTo(150);
    await tester.pump();
    await tester.pump();
    expect(
      tester.getBottomLeft(find.byKey(_stripKey, skipOffstage: false)).dy,
      lessThan(0),
    );
    final hidden = controller.offset;
    await _advance(tester, const Duration(seconds: 2));
    expect(controller.offset, closeTo(hidden, .01));
    vertical.jumpTo(20);
    await tester.pump();
    await _advance(tester, const Duration(seconds: 1));
    expect(controller.offset - hidden, closeTo(12, 1));
    await _dispose(tester);
  });
}
