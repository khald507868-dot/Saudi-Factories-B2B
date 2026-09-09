import 'package:flutter/material.dart';

import '../core/currency.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../pages/product_page.dart';
import '../services/factory_service.dart';
import 'common.dart';
import 'price_text.dart';

/// صور المنتج تُسحب باللمس، مع الحفاظ على فتح تفاصيل المنتج.
class CatalogProductCard extends StatelessWidget {
  const CatalogProductCard({super.key, required this.product});
  final SFProduct product;

  @override
  Widget build(BuildContext context) {
    final factory = product.raw['factories'] as Map?;
    final currency = SFCurrency.instance;
    final price = product.minPrice <= 0
        ? context.t('product_price_on_request')
        : product.minPrice == product.maxPrice
        ? currency.format(product.minPrice)
        : '${currency.format(product.minPrice, withSymbol: false)} – ${currency.format(product.maxPrice)}';
    void open() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProductPage(product: product)));
    return Material(
      color: SFColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        side: const BorderSide(color: SFColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ProductImageGallery(images: product.images, onTap: open),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(36),
                    child: Text(
                      product.name.isEmpty ? '—' : product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Tooltip(
                    message: price,
                    child: SFPriceText(
                      price,
                      textDirection: product.minPrice > 0
                          ? TextDirection.ltr
                          : context.i18n.direction,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: SFColors.darkGreen,
                      ),
                    ),
                  ),
                  if ((factory?['name'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            factory!['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: SFColors.muted2,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (factory['status'] == 'approved') ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: context.t('product_verified'),
                            child: const Icon(
                              Icons.verified,
                              size: 14,
                              color: SFColors.midGreen,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductImageGallery extends StatefulWidget {
  const ProductImageGallery({super.key, required this.images, this.onTap});
  final List<String> images;
  final VoidCallback? onTap;
  @override
  State<ProductImageGallery> createState() => _ProductImageGalleryState();
}

class _ProductImageGalleryState extends State<ProductImageGallery> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SFImage(url: '', radius: 0);
    return ColoredBox(
      color: SFColors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (_, index) => GestureDetector(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SFImage(
                  url: widget.images[index],
                  radius: 0,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          if (widget.images.length > 1)
            PositionedDirectional(
              bottom: 8,
              end: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: SFColors.white.withValues(alpha: .95),
                    border: Border.all(color: SFColors.border),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_index + 1}/${widget.images.length}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 10,
                      color: SFColors.muted2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
