import 'package:flutter_test/flutter_test.dart';
import 'package:saudi_factories/core/supabase_config.dart';
import 'package:saudi_factories/services/promotion_service.dart';

const _uid = '4e1e7e9e-b282-41c1-a889-a019b3eb4ac0';
const _path = '$_uid/promotions/discount_2026.webp';
const _image = '$kSupabaseUrl/storage/v1/object/public/promotion-media/$_path';

void _validate({
  String title = 'تخفيضات المصانع',
  String imageUrl = _image,
  String targetUrl = '',
  int sortOrder = 0,
}) => SFPromotion.validateInput(
  title: title,
  imageUrl: imageUrl,
  targetUrl: targetUrl,
  sortOrder: sortOrder,
);

void main() {
  test('سجل الإعلان يحافظ على إخفائه وترتيبه ورابطه عند التحويل', () {
    final json = {
      'id': 'a4e712e5-c595-41d9-93b5-fee93036e3c0',
      'title': 'خصومات اليوم',
      'image_url': _image,
      'target_url': 'https://example.com/offers?category=steel',
      'is_active': false,
      'sort_order': 23,
    };
    final promotion = SFPromotion.fromJson(json);
    expect(promotion.toJson(), json);
    expect(promotion.isActive, isFalse);
  });

  test('عنوان عربي وصورة مرفوعة يكفيان لإنشاء إعلان بلا رابط', () {
    expect(_validate, returnsNormally);
    expect(
      () => _validate(
        title: '  خصومات 20%  ',
        targetUrl: 'https://example.com/products?offer=20#details',
        sortOrder: 9999,
      ),
      returnsNormally,
    );
  });

  test('العنوان والترتيب لا يقبلان قيماً خارج حدود الحفظ', () {
    for (final title in ['', '   ', List.filled(121, 'خ').join()]) {
      expect(
        () => _validate(title: title),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'code',
            'promotion_title_invalid',
          ),
        ),
      );
    }
    expect(
      () => _validate(title: List.filled(120, 'خ').join()),
      returnsNormally,
    );
    for (final sortOrder in [-1, 10000]) {
      expect(
        () => _validate(sortOrder: sortOrder),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'code',
            'promotion_order_invalid',
          ),
        ),
      );
    }
  });

  test('وجهة الإعلان تسمح بـ HTTPS وتمنع السكربتات وبيانات الدخول', () {
    for (final target in [
      'javascript:alert(1)',
      'data:text/html,hello',
      'file:///etc/passwd',
      'http://example.com',
      '//example.com',
      '/offers',
      'https://',
      'https://admin:password@example.com',
      'https://example.com/offers today',
      'https://example.com/${List.filled(2048, 'a').join()}',
    ]) {
      expect(SFPromotion.isValidTargetUrl(target), isFalse, reason: target);
      expect(
        () => _validate(targetUrl: target),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'code',
            'promotion_link_invalid',
          ),
        ),
      );
    }
    expect(SFPromotion.isValidTargetUrl(''), isTrue);
    expect(
      SFPromotion.isValidTargetUrl(' https://example.com/offers?q=20%25 '),
      isTrue,
    );
  });

  test('تنظيف الصور لا يقبل دلو مشروع آخر أو مساراً ملتبساً', () {
    expect(PromotionService.imagePath(_image), _path);
    for (final imageUrl in [
      '',
      _image.replaceFirst(kSupabaseUrl, 'https://other.supabase.co'),
      _image.replaceFirst('promotion-media', 'factory-media'),
      _image.replaceFirst('https://', 'http://'),
      _image.replaceFirst('https://', 'https://admin@'),
      '$_image?download=1',
      '$_image#anything',
      _image.replaceFirst('discount_2026.webp', '../other.webp'),
      _image.replaceFirst('discount_2026.webp', '%2e%2e%2fother.webp'),
      _image.replaceFirst('.webp', '.svg'),
      _image.replaceFirst('$_uid/', ''),
    ]) {
      expect(PromotionService.imagePath(imageUrl), isNull, reason: imageUrl);
      expect(
        () => _validate(imageUrl: imageUrl),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'code',
            'promotion_image_required',
          ),
        ),
      );
    }
  });

  test('الزائر لا يدير إعلاناً أو ينظف صورة ولا يطلق إشعار نجاح', () async {
    // لا حاجة لعميل Supabase: الحارس يجب أن يرفض قبل أي طلب شبكة.
    const promotion = SFPromotion(
      id: 'a4e712e5-c595-41d9-93b5-fee93036e3c0',
      title: 'خصومات',
      imageUrl: _image,
    );
    final initialChanges = PromotionService.changes.value;
    await expectLater(PromotionService.listAdmin(), throwsStateError);
    await expectLater(
      PromotionService.save(
        title: promotion.title,
        imageUrl: promotion.imageUrl,
        targetUrl: '',
        isActive: true,
        sortOrder: 0,
      ),
      throwsStateError,
    );
    await expectLater(
      PromotionService.setActive(promotion, false),
      throwsStateError,
    );
    await expectLater(PromotionService.delete(promotion), throwsStateError);
    await expectLater(
      PromotionService.cleanupUploadedImage(_image),
      throwsStateError,
    );
    expect(PromotionService.changes.value, initialChanges);
  });
}
