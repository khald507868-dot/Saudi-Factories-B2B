import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/core/supabase_config.dart';
import 'package:saudi_factories/services/video_promotion_service.dart';
import 'package:saudi_factories/widgets/home_video_promotions.dart';

const media =
    '$kSupabaseUrl/storage/v1/object/public/video-promotion-media/11111111-1111-4111-8111-111111111111/ads';
const ad = SFVideoPromotion(
  id: 'one',
  title: 'عرض المصنع',
  imageUrl: '$media/cover.png',
  videoUrl: '$media/clip.mp4',
  logoUrl: '$media/logo.png',
);
const hidden = SFVideoPromotion(
  id: 'hidden',
  title: 'مسودة',
  imageUrl: '$media/cover.png',
  videoUrl: '$media/clip.mp4',
  isActive: false,
);

Widget host(Widget child, {String lang = 'ar', double scale = 1}) => I18nScope(
  i18n: I18n(lang),
  child: MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Scaffold(body: child),
  ),
);

class FakeVideo extends VideoPlayerPlatform {
  int creates = 0;
  int plays = 0;
  int pauses = 0;
  int disposals = 0;
  bool fail = false;
  double volume = 1;
  final streams = <int, StreamController<VideoEvent>>{};
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++creates;
    streams[id] = StreamController<VideoEvent>.broadcast();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    scheduleMicrotask(() {
      if (fail) {
        streams[id]!.addError(
          PlatformException(code: 'video_error', message: 'video offline'),
        );
      } else {
        streams[id]!.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 10),
            size: const Size(200, 300),
          ),
        );
      }
    });
    return streams[id]!.stream;
  }

  @override
  Future<void> dispose(int id) async {
    disposals++;
    await streams[id]?.close();
  }

  @override
  Future<void> play(int id) async {
    plays++;
  }

  @override
  Future<void> pause(int id) async {
    pauses++;
  }

  @override
  Future<void> setVolume(int id, double value) async {
    volume = value;
  }

  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> seekTo(int id, Duration value) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.green);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeVideo platform;
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    platform = FakeVideo();
    VideoPlayerPlatform.instance = platform;
  });

  test('video, cover and logo accept only this project bucket and correct media types', () {
    SFVideoPromotion.validateInput(
      title: ad.title,
      imageUrl: ad.imageUrl,
      videoUrl: ad.videoUrl,
      logoUrl: ad.logoUrl,
      targetUrl: '',
      sortOrder: 0,
    );
    expect(VideoPromotionService.imagePath(ad.videoUrl), isNull);
    expect(VideoPromotionService.imagePath(ad.imageUrl, video: true), isNull);
    expect(
      VideoPromotionService.imagePath(ad.videoUrl, video: true),
      endsWith('clip.mp4'),
    );
    expect(VideoPromotionService.imagePath('${ad.imageUrl}?token=bad'), isNull);
    expect(
      VideoPromotionService.imagePath(
        ad.imageUrl.replaceFirst(kSupabaseUrl, 'https://other.test'),
      ),
      isNull,
    );
    expect(
      () => SFVideoPromotion.validateInput(
        title: ad.title,
        imageUrl: ad.imageUrl,
        videoUrl: '',
        targetUrl: '',
        sortOrder: 0,
      ),
      throwsFormatException,
    );
    expect(SFVideoPromotion.isValidTargetUrl('javascript:alert(1)'), isFalse);
  });

  testWidgets('visitors see no drafts, admin controls, or empty/error gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        HomeVideoPromotions(promotions: Future.value([hidden]), onRetry: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VideoAdCard), findsNothing);
    expect(find.byKey(const ValueKey('home-video-ads')), findsNothing);
    final failed = Completer<List<SFVideoPromotion>>();
    await tester.pumpWidget(
      host(HomeVideoPromotions(promotions: failed.future, onRetry: () {})),
    );
    failed.completeError(StateError('missing table'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-video-ads')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final lang in ['ar', 'en']) {
    testWidgets(
      'portrait cards keep captions below and defer video loading: $lang',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SFVideoPromotion? selected;
        await tester.pumpWidget(
          host(
            HomeVideoPromotions(
              promotions: Future.value([ad, hidden]),
              onRetry: () {},
              onOpen: (value) => selected = value,
            ),
            lang: lang,
            scale: 1.3,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(VideoAdCard), findsOneWidget);
        expect(find.text(hidden.title), findsNothing);
        final card = tester.getRect(find.byType(VideoAdCard));
        expect(
          tester.getTopLeft(find.text(ad.title)).dy,
          greaterThan(card.top + 228),
        );
        expect(platform.creates, 0);
        await tester.tap(find.byType(VideoAdCard));
        expect(selected, ad);
        expect(platform.creates, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'video starts muted on request, pauses in background and releases on close',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(host(const VideoAdPlayer(ad: ad)));
      await tester.pumpAndSettle();
      expect(platform.creates, 1);
      expect(platform.plays, greaterThan(0));
      expect(platform.volume, 0);
      await tester.tap(find.byTooltip('تشغيل الصوت'));
      await tester.pump();
      expect(platform.volume, 1);
      final before = platform.pauses;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(platform.pauses, greaterThan(before));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(platform.disposals, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed video offers retry without exposing backend errors', (
    tester,
  ) async {
    platform.fail = true;
    await tester.pumpWidget(host(const VideoAdPlayer(ad: ad)));
    await tester.pumpAndSettle();
    expect(find.text('تعذّر تشغيل المقطع'), findsOneWidget);
    expect(find.text('video offline'), findsNothing);
    platform.fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('تعذّر تشغيل المقطع'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
