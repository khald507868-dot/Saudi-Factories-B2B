import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:saudi_factories/core/theme.dart';
import 'package:saudi_factories/widgets/promotion_image_appearance.dart';

Future<ui.Image> _image(void Function(ui.Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(200, 120);
    addTearDown(image.dispose);
    return image;
  } finally {
    picture.dispose();
  }
}

void _nearColor(ui.Color actual, ui.Color expected) {
  expect(actual.a, 1);
  expect(actual.r, closeTo(expected.r, 1 / 255));
  expect(actual.g, closeTo(expected.g, 1 / 255));
  expect(actual.b, closeTo(expected.b, 1 / 255));
}

double _contrast(ui.Color first, ui.Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('يستخرج اللون الفاتح والداكن ويحافظ على الصورة الأصلية', () async {
    for (final color in [
      const ui.Color(0xFFFFE04A),
      const ui.Color(0xFF173A27),
    ]) {
      final image = await _image(
        (canvas) => canvas.drawColor(color, ui.BlendMode.src),
      );
      _nearColor(await promotionHeaderColor(image), color);
      // يستطيع صاحب الصورة استخدامها بعد استخراج اللون.
      expect(await image.toByteData(), isNotNull);
    }
  });

  test(
    'يقيس الشريط العلوي ويتجاهل الجسم المختلف والزوايا والشعار الصغير',
    () async {
      const top = ui.Color(0xFFF4CD43);
      final image = await _image((canvas) {
        canvas.drawColor(const ui.Color(0xFF173A27), ui.BlendMode.src);
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 200, 24),
          ui.Paint()..color = top,
        );
        for (final corner in [
          const ui.Rect.fromLTWH(0, 0, 20, 24),
          const ui.Rect.fromLTWH(180, 0, 20, 24),
        ]) {
          canvas.drawRect(corner, ui.Paint()..color = SFColors.white);
        }
        canvas.drawRect(
          const ui.Rect.fromLTWH(80, 0, 40, 14),
          ui.Paint()..color = const ui.Color(0xFF000000),
        );
      });
      _nearColor(await promotionHeaderColor(image), top);
    },
  );

  test('يركب الخلفية الشفافة وشبه الشفافة على خلفية التطبيق', () async {
    final transparent = await _image(
      (canvas) =>
          canvas.drawColor(const ui.Color(0x00000000), ui.BlendMode.src),
    );
    _nearColor(await promotionHeaderColor(transparent), SFColors.surfaceAlt);

    const translucent = ui.Color(0x801F6B42);
    final image = await _image(
      (canvas) => canvas.drawColor(translucent, ui.BlendMode.src),
    );
    _nearColor(
      await promotionHeaderColor(image),
      ui.Color.alphaBlend(translucent, SFColors.surfaceAlt),
    );
  });

  test('يحافظ على لون الهوية للخلفية الفاتحة ويختار نصاً مقروءاً للداكنة', () {
    expect(promotionHeaderForeground(SFColors.white), SFColors.darkGreen);
    expect(promotionHeaderForeground(SFColors.darkGreen), SFColors.white);
    // الرمادي المتوسط يحتاج أسود، إذ لا يكفي تباين أخضر الهوية.
    const gray = ui.Color(0xFF888888);
    expect(promotionHeaderForeground(gray), const ui.Color(0xFF000000));

    for (final background in [
      SFColors.white,
      SFColors.darkGreen,
      const ui.Color(0xFFFFE04A),
      const ui.Color(0xFF173A27),
      gray,
      const ui.Color(0xFF4477AA),
      const ui.Color(0x00000000),
    ]) {
      final foreground = promotionHeaderForeground(background);
      expect(
        _contrast(
          foreground,
          ui.Color.alphaBlend(background, SFColors.surfaceAlt),
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
