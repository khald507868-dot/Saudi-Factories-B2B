import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/promotion_service.dart';
import 'common.dart';
import 'promotion_image_appearance.dart';

/// مكان الإعلانات ثابت في ترتيب الرئيسية، والإضافة من المساحة الفارغة للمشرف وحده.
class HomePromotions extends StatefulWidget {
  const HomePromotions({
    super.key,
    required this.promotions,
    required this.onRetry,
    this.onManage,
    this.onBackgroundColorChanged,
  });

  final Future<List<SFPromotion>> promotions;
  final VoidCallback onRetry;
  final VoidCallback? onManage;
  final ValueChanged<Color>? onBackgroundColorChanged;

  @override
  State<HomePromotions> createState() => _HomePromotionsState();
}

class _HomePromotionsState extends State<HomePromotions> {
  Color? _backgroundColor;

  void _reportBackgroundColor(Color color) {
    if (_backgroundColor == color) return;
    _backgroundColor = color;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _backgroundColor == color) {
        widget.onBackgroundColorChanged?.call(color);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SFPromotion>>(
    future: widget.promotions,
    builder: (context, snapshot) {
      // لا نعرض إعلاناً وهمياً أو خطأ تقنياً للزائر عند غياب الإعلانات.
      final items = (snapshot.data ?? <SFPromotion>[])
          .where((item) => item.isActive)
          .toList();
      if (items.isEmpty) {
        _reportBackgroundColor(
          widget.onManage == null ? SFColors.white : SFColors.surfaceAlt,
        );
        if (widget.onManage == null) return const SizedBox(height: 20);
      }
      return Padding(
        padding: EdgeInsets.only(bottom: items.length > 1 ? 4 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isNotEmpty)
              PromotionCarousel(
                promotions: items,
                onBackgroundColorChanged: _reportBackgroundColor,
              )
            else
              Material(
                color: SFColors.surfaceAlt,
                clipBehavior: Clip.hardEdge,
                child: InkWell(
                  onTap: widget.onManage,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.add_photo_alternate_outlined,
                          color: SFColors.midGreen,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.t('promo_empty_admin'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.t('promo_empty_hint'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: SFColors.muted2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (snapshot.hasError && widget.onManage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(context.t('promo_load_failed')),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// بانر بعرض الصفحة وارتفاع محدود، مع إظهار أسفل الصور الطويلة.
/// السحب يدوي، فلا يختفي الإعلان أثناء قراءته.
class PromotionCarousel extends StatefulWidget {
  const PromotionCarousel({
    super.key,
    required this.promotions,
    this.onOpen,
    this.onBackgroundColorChanged,
  });

  final List<SFPromotion> promotions;
  final ValueChanged<SFPromotion>? onOpen;
  final ValueChanged<Color>? onBackgroundColorChanged;

  @override
  State<PromotionCarousel> createState() => _PromotionCarouselState();
}

class _PromotionCarouselState extends State<PromotionCarousel> {
  static const double _minimumAspectRatio = 2.5;
  final _controller = PageController();
  int _page = 0;
  double _aspectRatio = _minimumAspectRatio;
  String? _imageUrl;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  int _imageVersion = 0;
  final _appearances = <String, ({double aspectRatio, Color color})>{};

  void _reportBackgroundColor(Color color) {
    final version = _imageVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && version == _imageVersion) {
        widget.onBackgroundColorChanged?.call(color);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchImageSize();
  }

  void _watchImageSize() {
    if (widget.promotions.isEmpty) {
      _stopWatchingImage();
      ++_imageVersion;
      _imageUrl = null;
      _aspectRatio = _minimumAspectRatio;
      return;
    }
    final url = widget.promotions[_page].imageUrl;
    if (url == _imageUrl) return;
    _stopWatchingImage();
    final version = ++_imageVersion;
    _imageUrl = url;
    final cached = _appearances[url];
    if (cached != null) {
      _aspectRatio = cached.aspectRatio;
      _reportBackgroundColor(cached.color);
      return;
    }
    _aspectRatio = _minimumAspectRatio;
    _reportBackgroundColor(SFColors.surfaceAlt);
    final stream = NetworkImage(url)
        .resolve(createLocalImageConfiguration(context));
    _imageStream = stream;
    _imageListener = ImageStreamListener(
      (info, synchronousCall) {
        final ratio = info.image.width / info.image.height;
        // The cached image may resolve while the carousel is building.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || _imageStream != stream) {
            info.dispose();
            return;
          }
          _stopWatchingImage();
          if (_aspectRatio != ratio) setState(() => _aspectRatio = ratio);
          var color = SFColors.surfaceAlt;
          try {
            color = await promotionHeaderColor(info.image);
          } catch (_) {
            // Keep the banner usable if pixel reading is unavailable.
          } finally {
            info.dispose();
          }
          if (!mounted || version != _imageVersion) return;
          _appearances[url] = (aspectRatio: ratio, color: color);
          widget.onBackgroundColorChanged?.call(color);
        });
      },
      onError: (Object error, StackTrace? stack) {
        // Image.network below displays the existing error fallback.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _imageStream == stream) _stopWatchingImage();
        });
      },
    );
    _imageStream!.addListener(_imageListener!);
  }

  void _stopWatchingImage() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  @override
  void didUpdateWidget(covariant PromotionCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.promotions.map((item) => item.id).join(',');
    final newIds = widget.promotions.map((item) => item.id).join(',');
    if (oldIds != newIds) {
      _page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(0);
      });
    }
    final urls = widget.promotions.map((item) => item.imageUrl).toSet();
    _appearances.removeWhere((url, _) => !urls.contains(url));
    _watchImageSize();
  }

  @override
  void dispose() {
    _stopWatchingImage();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(SFPromotion promotion) async {
    if (widget.onOpen != null) {
      widget.onOpen!(promotion);
      return;
    }
    final uri = Uri.tryParse(promotion.targetUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showSFMessage(context, context.t('fx_failed'));
      }
    } catch (error) {
      if (mounted) showSFError(context, error);
    }
  }

  void _select(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(index);
    } else {
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.promotions.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: const BoxDecoration(color: SFColors.white),
          clipBehavior: Clip.hardEdge,
          child: AspectRatio(
            aspectRatio: _aspectRatio < _minimumAspectRatio
                ? _minimumAspectRatio
                : _aspectRatio,
            child: PageView.builder(
              key: const ValueKey('home-promotion-pages'),
              controller: _controller,
              itemCount: widget.promotions.length,
              onPageChanged: (page) => setState(() {
                _page = page;
                _watchImageSize();
              }),
              itemBuilder: (context, index) {
                final promotion = widget.promotions[index];
                final hasLink = promotion.targetUrl.isNotEmpty;
                return Semantics(
                  label: promotion.title,
                  image: true,
                  button: hasLink,
                  link: hasLink,
                  onTap: hasLink ? () => _open(promotion) : null,
                  excludeSemantics: true,
                  child: Material(
                    color: SFColors.surfaceAlt,
                    child: InkWell(
                      onTap: hasLink ? () => _open(promotion) : null,
                      child: Image.network(
                        promotion.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        alignment: Alignment.bottomCenter,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const Center(
                                child: SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                        errorBuilder: (context, error, stack) => Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.local_offer_outlined,
                                color: SFColors.midGreen,
                                size: 28,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                promotion.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.promotions.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (var index = 0; index < widget.promotions.length; index++)
                  Semantics(
                    label: context
                        .t('promo_position')
                        .replaceAll('{current}', '${index + 1}')
                        .replaceAll('{total}', '${widget.promotions.length}'),
                    selected: _page == index,
                    button: true,
                    onTap: () => _select(index),
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: () => _select(index),
                      radius: 20,
                      child: SizedBox.square(
                        dimension: 44,
                        child: Center(
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                            width: _page == index ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _page == index
                                  ? SFColors.darkGreen
                                  : SFColors.border,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
