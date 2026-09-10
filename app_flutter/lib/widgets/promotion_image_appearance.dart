import 'dart:ui' as ui;

import '../core/theme.dart';

/// يستخرج لون أعلى الإعلان من عينة صغيرة، مع تجاهل زواياه الجانبية.
/// تبقى ملكية الصورة الأصلية للمستدعي؛ تُحرر الصور المؤقتة فقط.
Future<ui.Color> promotionHeaderColor(ui.Image image) async {
  const sampleWidth = 24;
  const sampleHeight = 6;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  ui.Picture? picture;
  ui.Image? sample;
  try {
    // تركيب الشفافية على خلفية التطبيق قبل قياس اللون.
    canvas.drawColor(SFColors.surfaceAlt, ui.BlendMode.src);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTRB(
        image.width * .08,
        0,
        image.width * .92,
        (image.height * .12).clamp(1.0, image.height.toDouble()),
      ),
      ui.Rect.fromLTWH(0, 0, sampleWidth.toDouble(), sampleHeight.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    picture = recorder.endRecording();
    sample = await picture.toImage(sampleWidth, sampleHeight);
    final bytes = await sample.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) throw StateError('promotion_color_unavailable');

    // الوسيط يقاوم النصوص والشعارات الصغيرة التي تخالف لون الخلفية.
    final red = <int>[];
    final green = <int>[];
    final blue = <int>[];
    for (var index = 0; index < bytes.lengthInBytes; index += 4) {
      red.add(bytes.getUint8(index));
      green.add(bytes.getUint8(index + 1));
      blue.add(bytes.getUint8(index + 2));
    }
    red.sort();
    green.sort();
    blue.sort();
    final middle = red.length ~/ 2;
    return ui.Color.fromARGB(255, red[middle], green[middle], blue[middle]);
  } finally {
    sample?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
  }
}

/// يبقي الأخضر الداكن متى كان مقروءاً، وإلا يختار الأعلى تبايناً.
ui.Color promotionHeaderForeground(ui.Color background) {
  final opaque = ui.Color.alphaBlend(background, SFColors.surfaceAlt);
  if (_contrast(SFColors.darkGreen, opaque) >= 4.5) return SFColors.darkGreen;
  const black = ui.Color(0xFF000000);
  return _contrast(black, opaque) >= _contrast(SFColors.white, opaque)
      ? black
      : SFColors.white;
}

double _contrast(ui.Color foreground, ui.Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first >= second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}
