import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/currency.dart';
import '../services/favorites_service.dart';
import '../widgets/common.dart';
import '../widgets/price_text.dart';
import 'product_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<SFFavorite> _items = [];
  final Set<int> _removing = {};
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await SFFavorites.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _remove(SFFavorite favorite) async {
    final id = favorite.product.id;
    if (_removing.contains(id)) return;
    setState(() => _removing.add(id));
    try {
      await SFFavorites.remove(id);
      if (!mounted) return;
      setState(() => _items.removeWhere((item) => item.product.id == id));
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _removing.remove(id));
    }
  }

  Future<void> _open(SFFavorite favorite) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductPage(product: favorite.product)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(title: context.t('dash_favorites'), showBack: true),
      body: _loading
          ? SFStateView(message: context.t('fx_loading'), loading: true)
          : _error != null
          ? SFStateView(
              message: context.t('app_load_error'),
              icon: Icons.wifi_off_outlined,
              onRetry: _load,
              retryLabel: context.t('app_retry'),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_items.isEmpty)
                    SFStateView(
                      message:
                          '${context.t('fav_empty')}\n${context.t('fav_empty_hint')}',
                      icon: Icons.favorite_border,
                    ),
                  for (final favorite in _items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(SFMetrics.radius),
                        onTap: () => _open(favorite),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              SFImage(
                                url: favorite.product.image,
                                width: 76,
                                height: 76,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      favorite.product.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (favorite.factoryName.isNotEmpty)
                                      Text(
                                        favorite.factoryName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: SFColors.muted2,
                                          fontSize: 12,
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    SFPriceText(
                                      SFCurrency.instance.format(
                                        favorite.product.minPrice,
                                      ),
                                      style: const TextStyle(
                                        color: SFColors.midGreen,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: context.t('fav_remove'),
                                onPressed:
                                    _removing.contains(favorite.product.id)
                                    ? null
                                    : () => _remove(favorite),
                                icon: _removing.contains(favorite.product.id)
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.favorite,
                                        color: SFColors.danger,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
