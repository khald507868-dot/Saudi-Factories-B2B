import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/currency.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/factory_service.dart';
import '../services/reviews_service.dart';
import 'price_text.dart';

/// تقييم المنتج وسعره تحت الصورة والاسم في شريط الرئيسية.
class HomeProductDetails extends StatelessWidget {
  const HomeProductDetails({
    super.key,
    required this.product,
    this.rating,
    this.ratingLoading = false,
    this.ratingFailed = false,
  });

  final SFProduct product;
  final SFProductRating? rating;
  final bool ratingLoading;
  final bool ratingFailed;

  static const _fontSize = 11.0;
  static const _lineHeight = 1.3;
  static const _gap = 4.0;

  static double _ratingHeight(BuildContext context) => math.max(
    14,
    MediaQuery.textScalerOf(context).scale(_fontSize) * _lineHeight,
  );

  static double _priceHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_fontSize) * _lineHeight * 2;

  /// يحجز سطر التقييم وسطرَي السعر مع احترام تكبير النص.
  static double heightFor(BuildContext context) =>
      _ratingHeight(context) + _gap + _priceHeight(context);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    height: heightFor(context),
    child: ListenableBuilder(
      listenable: SFCurrency.instance,
      builder: (context, _) {
        final i18n = context.i18n;
        final currency = SFCurrency.instance;
        final minimum = product.minPrice;
        final maximum = product.maxPrice;
        final price = minimum <= 0
            ? i18n.t('product_price_on_request')
            : minimum == maximum
            ? currency.format(minimum)
            : '${currency.format(minimum, withSymbol: false)} – ${currency.format(maximum)}';
        final currentRating = rating;
        final hasRating =
            !ratingLoading &&
            !ratingFailed &&
            currentRating != null &&
            currentRating.count > 0 &&
            currentRating.average.isFinite &&
            currentRating.average >= 1 &&
            currentRating.average <= 5;
        final noReviews =
            !ratingLoading && !ratingFailed && currentRating?.count == 0;
        final ratingText = ratingLoading
            ? '…'
            : hasRating
            ? '${currentRating.average.toStringAsFixed(1)} (${currentRating.count})'
            : noReviews
            ? '— (0)'
            : '—';
        final ratingHint = ratingLoading
            ? i18n.t('fx_loading')
            : ratingFailed
            ? i18n.t('fx_failed')
            : noReviews
            ? i18n.t('reviews_none')
            : '${i18n.t('reviews_title')}: $ratingText';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _ratingHeight(context),
              child: Tooltip(
                message: ratingHint,
                excludeFromSemantics: true,
                child: Semantics(
                  label: ratingHint,
                  excludeSemantics: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    textDirection: TextDirection.ltr,
                    children: [
                      Icon(
                        hasRating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 14,
                        color: hasRating ? SFColors.gold : SFColors.muted2,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          ratingText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: _fontSize,
                            height: _lineHeight,
                            color: SFColors.muted2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: _gap),
            SizedBox(
              height: _priceHeight(context),
              child: Tooltip(
                message: price,
                child: SFPriceText(
                  price,
                  textAlign: TextAlign.center,
                  textDirection: minimum > 0
                      ? TextDirection.ltr
                      : i18n.direction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: _fontSize,
                    height: _lineHeight,
                    fontWeight: FontWeight.w700,
                    color: SFColors.darkGreen,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
