// ============================================================
//  قائمة المصانع — مقابل app-factories.html
//
//  لا نُضيف eq('status','approved') هنا: سياسات RLS هي من
//  تُصفّي الصفوف، وإضافة الشرط تُخفي مصنع المالك المعلّق عنه.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/i18n_data.dart';
import '../core/theme.dart';
import '../services/factory_service.dart';
import '../widgets/common.dart';
import 'factory_page.dart';

class FactoriesPage extends StatefulWidget {
  const FactoriesPage({
    super.key,
    this.initialCategory,
    this.categoryLabel,
    this.initialSearch,
    this.initialRegion,
  });

  /// الاسم الإنجليزي للفئة — مفتاح الربط مع عمود industry.
  final String? initialCategory;

  /// الاسم المعروض للفئة بلغة المستخدم.
  final String? categoryLabel;

  final String? initialSearch;
  final String? initialRegion;

  /// هل فُتحت كصفحة مستقلة (بزر رجوع) أم كتبويب في الهيكل؟
  bool get isFiltered =>
      (initialRegion != null && initialRegion!.isNotEmpty) ||
      (initialCategory != null && initialCategory!.isNotEmpty) ||
      (initialSearch != null && initialSearch!.isNotEmpty);

  @override
  State<FactoriesPage> createState() => _FactoriesPageState();
}

class _FactoriesPageState extends State<FactoriesPage> {
  late Future<List<SFFactory>> _future;
  String _search = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search = widget.initialSearch ?? '';
    _future = _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<SFFactory>> _load() => FactoryService.list(
    category: widget.initialCategory,
    search: _search,
    region: widget.initialRegion,
  );

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _search = q;
        _future = _load();
      });
    });
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(
        title: widget.initialCategory != null
            ? _categoryName(i18n, widget.initialCategory!)
            : widget.initialRegion != null
            ? i18n.regionName(widget.initialRegion!)
            : i18n.t('nav_factories'),
        showBack: widget.isFiltered,
        searchHint: i18n.t('search_placeholder'),
        onSearchChanged: _onSearch,
        onSearchSubmitted: _onSearch,
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              color: SFColors.midGreen,
              child: FutureBuilder<List<SFFactory>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return SFStateView(
                      message: i18n.t('fx_loading'),
                      loading: true,
                    );
                  }
                  if (snap.hasError) {
                    return SFStateView(
                      message: i18n.t('fx_failed'),
                      icon: Icons.cloud_off,
                      onRetry: _reload,
                    );
                  }
                  final items = snap.data ?? [];
                  if (items.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 80),
                        SFStateView(message: i18n.t('fx_empty')),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) =>
                        _FactoryCard(factory: items[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactoryCard extends StatelessWidget {
  const _FactoryCard({required this.factory});

  final SFFactory factory;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    final location = _locationName(i18n, factory);
    return Material(
      color: SFColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        side: const BorderSide(color: SFColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FactoryPage(factoryId: factory.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SFImage(
                url: factory.logo,
                width: 60,
                height: 60,
                radius: 12,
                fit: BoxFit.contain,
                placeholderIcon: Icons.factory_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            factory.name.isEmpty ? '—' : factory.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                            ),
                          ),
                        ),
                        if (factory.isApproved) ...[
                          const SizedBox(width: 5),
                          Tooltip(
                            message: i18n.t('product_verified'),
                            child: const Icon(
                              Icons.verified,
                              size: 15,
                              color: SFColors.midGreen,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (factory.industry.isNotEmpty)
                      Text(
                        _categoryName(i18n, factory.industry),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: SFColors.muted2,
                        ),
                      ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: SFColors.muted2,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: SFColors.muted2,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // حالة المصنع تظهر لصاحبه فقط — العامة لا يرون إلا المعتمد.
                    if (factory.isMine && !factory.isApproved) ...[
                      const SizedBox(height: 8),
                      SFStatusChip(
                        status: factory.status,
                        label: i18n.t(switch (factory.status) {
                          'approved' => 'fs_approved',
                          'rejected' => 'fs_rejected',
                          _ => 'fs_pending',
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                i18n.isRtl ? Icons.chevron_left : Icons.chevron_right,
                size: 20,
                color: SFColors.muted2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _categoryName(I18n i18n, String value) {
  for (final category in i18n.categories) {
    if (category.values.any(
      (name) => name.toLowerCase() == value.trim().toLowerCase(),
    )) {
      return i18n.categoryName(category);
    }
  }
  return value;
}

String _locationName(I18n i18n, SFFactory factory) {
  final city = factory.city.trim();
  if (city.isEmpty) return i18n.regionName(factory.regionId);
  for (final region in kRegionNames.entries) {
    if (region.key.toLowerCase() == city.toLowerCase() ||
        region.value.values.any(
          (name) => name.toLowerCase() == city.toLowerCase(),
        )) {
      return i18n.regionName(region.key);
    }
  }
  return city;
}
