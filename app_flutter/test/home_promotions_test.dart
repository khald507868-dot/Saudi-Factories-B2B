import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/services/promotion_service.dart';
import 'package:saudi_factories/widgets/home_promotions.dart';
import 'package:saudi_factories/widgets/promotion_artwork.dart';

const first = SFPromotion(
  id: 'first',
  title: 'عرض المصنع الأول',
  imageUrl: 'https://example.com/banner-one.png',
  targetUrl: 'https://example.com/offer-one',
);
const second = SFPromotion(
  id: 'second',
  title: 'عرض المصنع الثاني',
  imageUrl: 'https://example.com/banner-two.png',
);
const hidden = SFPromotion(
  id: 'hidden',
  title: 'عرض مخفي',
  imageUrl: 'https://example.com/hidden.png',
  isActive: false,
);

Widget host(Widget child, {String language = 'ar', double width = 320}) =>
    I18nScope(
      i18n: I18n(language),
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 700),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Directionality(
            textDirection: language == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _cacheImage(
  WidgetTester tester,
  String url,
  int width,
  int height,
) async {
  final image = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const Color(0xFFFFD740), ui.BlendMode.src);
    // مساحة العرض أسفل صورة طويلة، كما في صورة التطبيق المرجعية.
    canvas.drawRect(
      Rect.fromLTWH(0, height * .7, width.toDouble(), height * .3),
      Paint()..color = const Color(0xFF123D29),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  });
  final key = await NetworkImage(url).obtainKey(ImageConfiguration.empty);
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
  );
  addTearDown(() => PaintingBinding.instance.imageCache.evict(key));
  await tester.pump();
}

Future<void> _settleImage(WidgetTester tester) async {
  for (var phase = 0; phase < 3; phase++) {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final campaign in const {
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/113c9df0-2d9f-440d-8e6d-64d6f94c2548.png':
        'cleaning',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/8936d669-60a2-4e9a-89ab-2fae15085cef.png':
        'plastics',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/cb537159-8914-45fe-99e3-b9a4ef69ac68.png':
        'packaging',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/89d24e90-f9eb-47be-8e96-87435af7f392.png':
        'food-drinks',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/4287fb7c-4d67-41e6-a5b7-600b3e748713.png':
        'clothing-textiles',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/c6d14284-7a8b-45bb-a5f4-4b96c7eb4dad.png':
        'electronics',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/17fbad53-40f1-422c-b741-3034f9fc0910.png':
        'personal-care',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/db4b5564-4a40-4b59-8c30-06c72e240aba.png':
        'building-materials',
    'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/93887d65-b2c1-4114-9225-8a62488f17ff.png':
        'furniture',
  }.entries) {
    testWidgets('App banner ${campaign.value}: complete image, size and link', (
      tester,
    ) async {
      final promotion = SFPromotion(
        id: campaign.value,
        title: 'العناية الشخصية',
        imageUrl: campaign.key,
        targetUrl: 'https://example.com/personal-care',
      );
      SFPromotion? opened;
      await tester.pumpWidget(
        host(
          PromotionCarousel(
            promotions: [promotion],
            onOpen: (item) => opened = item,
          ),
          width: 430,
        ),
      );
      await _settleImage(tester);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        AssetImage('assets/promotions/${campaign.value}-landscape.png'),
      );
      final decoded = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect(decoded, isNotNull);
      expect(decoded!.width / decoded.height, closeTo(2.5, .07));
      expect(image.fit, BoxFit.cover);
      expect(tester.getSize(find.byType(PageView)).height, closeTo(172, 1));
      await tester.tap(find.byType(PageView));
      expect(opened, promotion);
      // A new uploaded image must not retain the old campaign's artwork.
      expect(
        promotionImageProvider('https://example.com/replacement.png'),
        isA<NetworkImage>(),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('الزائر لا يرى مسودات أو أدوات الإدارة أو مساحة إعلان فارغة', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(HomePromotions(promotions: Future.value([hidden]), onRetry: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PromotionCarousel), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.text('عرض مخفي'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('فشل خدمة الإعلانات لا يعطّل صفحة الزائر أو يعرض خطأً تقنياً', (
    tester,
  ) async {
    final response = Completer<List<SFPromotion>>();
    await tester.pumpWidget(
      host(HomePromotions(promotions: response.future, onRetry: () {})),
    );
    response.completeError(StateError('database unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(PromotionCarousel), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('المدير يفتح إضافة الإعلانات من المكان الفارغ', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      host(
        HomePromotions(
          promotions: Future.value([]),
          onRetry: () {},
          onManage: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('أضف إعلان تخفيضات'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ar', 'en']) {
    testWidgets('التنقّل والروابط والصورة كاملة على عرض 320: $language', (
      tester,
    ) async {
      SFPromotion? opened;
      await tester.pumpWidget(
        host(
          PromotionCarousel(
            promotions: const [first, second],
            onOpen: (item) => opened = item,
          ),
          language: language,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(PageView)).width,
        lessThanOrEqualTo(320),
      );
      expect(
        tester.widget<Image>(find.byType(Image).first).fit,
        BoxFit.contain,
      );
      await tester.tap(find.byType(PageView));
      expect(opened?.id, first.id);
      final dots = find.byType(InkResponse);
      // InkWell ليس InkResponse من حيث نوع runtime الذي يفحصه Finder.
      expect(dots, findsNWidgets(2));
      await tester.tap(dots.last);
      await tester.pumpAndSettle();
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.controller!.page, 1);
      opened = null;
      await tester.tap(find.byType(PageView));
      expect(opened, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('حذف الإعلان الحالي يعيد المؤشر إلى صورة موجودة دون خطأ', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const PromotionCarousel(promotions: [first, second])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(InkResponse).last);
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(const PromotionCarousel(promotions: [first])));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(find.byType(InkResponse), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 430.0]) {
    testWidgets('الصورة الطويلة تظهر كاملة داخل مساحة مناسبة للجوال: $width', (
      tester,
    ) async {
      const tall = SFPromotion(
        id: 'tall-banner',
        title: 'عرض أسفل صورة طويلة',
        imageUrl: 'https://example.com/tall-banner.png',
        targetUrl: 'https://example.com/tall-offer',
      );
      const wide = SFPromotion(
        id: 'wide-banner',
        title: 'عرض عريض',
        imageUrl: 'https://example.com/wide-banner.png',
      );
      await _cacheImage(tester, tall.imageUrl, 200, 600);
      await _cacheImage(tester, wide.imageUrl, 400, 100);
      SFPromotion? opened;
      await tester.pumpWidget(
        host(
          PromotionCarousel(
            promotions: const [tall, wide],
            onOpen: (promotion) => opened = promotion,
          ),
          width: width,
        ),
      );
      await _settleImage(tester);
      final page = find.byType(PageView);
      expect(tester.getSize(page).width, width);
      expect(tester.getSize(page).height, closeTo(width / 2.5, .01));
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.fit, BoxFit.contain);
      expect(image.alignment, Alignment.center);
      await tester.tap(page);
      expect(opened?.id, tall.id);

      // الصورة الأعرض تحتفظ بارتفاعها الطبيعي، ونقاط التنقل تبقى عاملة.
      await tester.tap(find.byType(InkResponse).last);
      await _settleImage(tester);
      expect(tester.widget<PageView>(page).controller!.page, 1);
      expect(tester.getSize(page), Size(width, width / 4));
      await tester.tap(find.byType(InkResponse).first);
      await _settleImage(tester);
      expect(tester.widget<PageView>(page).controller!.page, 0);
      expect(tester.getSize(page).height, closeTo(width / 2.5, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
