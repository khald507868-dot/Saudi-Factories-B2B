// ============================================================
//  قائمة المصانع — مقابل app-factories.html
//
//  لا نُضيف eq('status','approved') هنا: سياسات RLS هي من
//  تُصفّي الصفوف، وإضافة الشرط تُخفي مصنع المالك المعلّق عنه.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
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
  });

  /// الاسم الإنجليزي للفئة — مفتاح الربط مع عمود industry.
  final String? initialCategory;

  /// الاسم المعروض للفئة بلغة المستخدم.
  final String? categoryLabel;

  final String? initialSearch;

  /// هل فُتحت كصفحة مستقلة (بزر رجوع) أم كتبويب في الهيكل؟
  bool get isFiltered =>
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
        showBack: widget.isFiltered,
        searchHint: i18n.t('search_placeholder'),
        onSearchChanged: _onSearch,
        onSearchSubmitted: _onSearch,
      ),
      body: Column(
        children: [
          if (widget.categoryLabel != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                widget.categoryLabel!,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
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

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FactoryPage(factoryId: factory.id),
          ),
        );
      },
      borderRadius: BorderRadius.circular(SFMetrics.radius),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SFColors.white,
          border: Border.all(color: SFColors.border),
          borderRadius: BorderRadius.circular(SFMetrics.radius),
        ),
        child: Row(
          children: [
            SFImage(
              url: factory.logo,
              width: 56,
              height: 56,
              radius: 10,
              placeholderIcon: Icons.factory_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    factory.name.isEmpty ? '—' : factory.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (factory.industry.isNotEmpty)
                    Text(
                      factory.industry,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SFColors.muted2,
                      ),
                    ),
                  if (factory.city.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      factory.city,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SFColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // حالة المصنع تظهر لصاحبه فقط — العامة لا يرون إلا المعتمد.
            if (factory.isMine && !factory.isApproved)
              SFStatusChip(
                status: factory.status,
                label: i18n.t(switch (factory.status) {
                  'approved' => 'fs_approved',
                  'rejected' => 'fs_rejected',
                  _ => 'fs_pending',
                }),
              ),
          ],
        ),
      ),
    );
  }
}
