import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/core/theme.dart';
import 'package:saudi_factories/pages/splash_page.dart';
import 'package:saudi_factories/pages/user_type_page.dart';
import 'package:saudi_factories/widgets/factory_welcome_illustration.dart';
import 'package:saudi_factories/widgets/wordmark.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late ByteData testFont;
  late bool originalRuntimeFetching;

  setUpAll(() async {
    originalRuntimeFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    // Preserve production text sizing and layout settings while using
    // Flutter's deterministic test font instead of a network font download.
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

  setUp(() {
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

  testWidgets('welcome stays for three seconds and replaces its route', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final observer = _ReplacementObserver();
    final i18n = I18n('ar');
    addTearDown(i18n.dispose);
    await tester.pumpWidget(
      _host(i18n: i18n, navigatorKey: navigator, observer: observer),
    );

    expect(find.byType(Wordmark), findsOneWidget);
    expect(find.byType(FactoryWelcomeIllustration), findsOneWidget);
    expect(find.text(i18n.t('splash_tagline')), findsOneWidget);
    expect(find.byType(UserTypePage), findsNothing);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.byType(UserTypePage), findsNothing);
    expect(observer.replacements, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(observer.replacements, 1);
    // Let Navigator build the newly scheduled route without advancing time.
    await tester.pump();
    expect(find.byType(UserTypePage), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(SplashPage), findsNothing);
    expect(find.byType(UserTypePage), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(await navigator.currentState!.maybePop(), isFalse);
    await tester.pump();
    expect(find.byType(UserTypePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing welcome cancels pending navigation and animation', (
    tester,
  ) async {
    final i18n = I18n('ar');
    addTearDown(i18n.dispose);
    await tester.pumpWidget(_host(i18n: i18n));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(UserTypePage), findsNothing);
    expect(tester.takeException(), isNull);
    expect(binding.transientCallbackCount, 0);
  });

  testWidgets('illustration animates during the welcome period', (
    tester,
  ) async {
    final i18n = I18n('ar');
    addTearDown(i18n.dispose);
    await tester.pumpWidget(_host(i18n: i18n));
    // Establish the first ticker frame after its post-frame start.
    await tester.pump();
    final illustration = tester.widget<FactoryWelcomeIllustration>(
      find.byType(FactoryWelcomeIllustration),
    );
    final initialValue = illustration.animation.value;
    await tester.pump(const Duration(milliseconds: 700));
    expect(illustration.animation.value, isNot(initialValue));
    expect(find.byType(UserTypePage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion keeps illustration still for the full three seconds',
    (tester) async {
      final i18n = I18n('ar');
      addTearDown(i18n.dispose);
      await tester.pumpWidget(_host(i18n: i18n, disableAnimations: true));
      final initialValue = tester
          .widget<FactoryWelcomeIllustration>(
            find.byType(FactoryWelcomeIllustration),
          )
          .animation
          .value;
      await tester.pump(const Duration(milliseconds: 1400));
      expect(
        tester
            .widget<FactoryWelcomeIllustration>(
              find.byType(FactoryWelcomeIllustration),
            )
            .animation
            .value,
        initialValue,
      );
      await tester.pump(const Duration(milliseconds: 1599));
      expect(find.byType(SplashPage), findsOneWidget);
      expect(find.byType(UserTypePage), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.byType(SplashPage), findsNothing);
      expect(find.byType(UserTypePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets(
      'welcome fits ${size.width} x ${size.height} with larger text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final i18n = I18n('ar');
        addTearDown(i18n.dispose);
        await tester.pumpWidget(_host(i18n: i18n, textScale: 1.3));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);

        for (final element in [
          find.byType(Wordmark),
          find.byType(FactoryWelcomeIllustration),
          find.text(i18n.t('splash_tagline')),
        ]) {
          expect(element, findsOneWidget);
          await tester.ensureVisible(element);
          await tester.pump();
          final rect = tester.getRect(element);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.overlaps(Offset.zero & size), isTrue);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Widget _host({
  required I18n i18n,
  GlobalKey<NavigatorState>? navigatorKey,
  NavigatorObserver? observer,
  double textScale = 1,
  bool disableAnimations = false,
}) {
  return I18nScope(
    i18n: i18n,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [?observer],
      theme: buildAppTheme().copyWith(splashFactory: InkRipple.splashFactory),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: const SplashPage(),
    ),
  );
}

class _ReplacementObserver extends NavigatorObserver {
  int replacements = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacements++;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
